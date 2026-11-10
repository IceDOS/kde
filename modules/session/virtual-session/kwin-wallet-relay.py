import asyncio
import sys

from jeepney import HeaderFields, MessageType, new_error
from jeepney.bus_messages import MatchRule, message_bus
from jeepney.io.asyncio import open_dbus_connection
from jeepney.low_level import MessageFlag

SECRETS = "org.freedesktop.secrets"
KWALLET = "org.kde.kwalletd6"
NAMES = (KWALLET, "org.kde.kwalletd5", "org.kde.kwalletd", "org.kde.ksecretd", SECRETS, "org.kde.secretservicecompat")
BUS_NAME = "org.freedesktop.DBus"


async def call(conn, message):
    serial = next(conn.outgoing_serial)
    await conn.send(message, serial=serial)
    while True:
        reply = await conn.receive()
        if reply.header.fields.get(HeaderFields.reply_serial) != serial:
            continue
        if reply.header.message_type == MessageType.error:
            raise RuntimeError(reply.body)
        return reply.body


def real_destination(destination, path):
    # GDBus proxies call the owner's unique name, which hides the wallet name they meant.
    if destination in NAMES:
        return destination
    return SECRETS if path.startswith("/org/freedesktop/secrets") else KWALLET


async def from_private(private, real, pending):
    while True:
        message = await private.receive()
        fields = message.header.fields
        if message.header.message_type != MessageType.method_call:
            continue
        client = fields.pop(HeaderFields.sender)
        fields[HeaderFields.destination] = real_destination(fields.get(HeaderFields.destination), fields[HeaderFields.path])
        serial = next(real.outgoing_serial)
        if not message.header.flags & MessageFlag.no_reply_expected:
            pending[serial] = (client, message.header.serial)
        await real.send(message, serial=serial)


async def from_real(private, real, pending):
    while True:
        message = await real.receive()
        fields = message.header.fields
        kind = message.header.message_type
        if kind == MessageType.method_call:
            if not message.header.flags & MessageFlag.no_reply_expected:
                await real.send(new_error(message, "org.freedesktop.DBus.Error.UnknownMethod", "s", ("no objects on relay",)))
            continue
        if kind == MessageType.signal:
            if fields.get(HeaderFields.sender) == BUS_NAME:
                continue
            fields.pop(HeaderFields.destination, None)
        else:
            target = pending.pop(fields.get(HeaderFields.reply_serial), None)
            if target is None:
                continue
            fields[HeaderFields.destination], fields[HeaderFields.reply_serial] = target
        fields.pop(HeaderFields.sender, None)
        await private.send(message)


async def main(private_address):
    private = await open_dbus_connection(private_address)
    real = await open_dbus_connection("SESSION")
    for name in (KWALLET, SECRETS):
        await call(real, message_bus.AddMatch(MatchRule(type="signal", sender=name)))
    for name in NAMES:
        await call(private, message_bus.RequestName(name))
    pending = {}
    await asyncio.gather(from_private(private, real, pending), from_real(private, real, pending))


asyncio.run(main(sys.argv[1]))
