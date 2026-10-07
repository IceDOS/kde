"""Small blocking D-Bus helpers over jeepney; every call returns None when the peer is missing."""
from jeepney import DBusAddress, DBusErrorResponse, MessageType, new_method_call
from jeepney.io.blocking import open_dbus_connection

_conns: dict = {}


def conn(bus: str):
    if bus not in _conns:
        _conns[bus] = open_dbus_connection(bus=bus)
    return _conns[bus]


def call(bus: str, service: str, path: str, iface: str, member: str, sig: str = "", args: tuple = (),
         timeout: float = 2.0):
    try:
        msg = new_method_call(DBusAddress(path, bus_name=service, interface=iface), member, sig or None, args)
        reply = conn(bus).send_and_get_reply(msg, timeout=timeout)
    except (DBusErrorResponse, OSError, TimeoutError, ValueError):
        return None
    # Blocking jeepney hands error replies back as messages instead of raising.
    if reply.header.message_type == MessageType.error:
        return None
    body = reply.body
    return body[0] if len(body) == 1 else body


def unwrap(v):
    """Strip jeepney's (signature, value) variant pairs, recursively."""
    if isinstance(v, tuple) and len(v) == 2 and isinstance(v[0], str) and _is_sig(v[0]):
        return unwrap(v[1])
    if isinstance(v, dict):
        return {k: unwrap(x) for k, x in v.items()}
    if isinstance(v, list):
        return [unwrap(x) for x in v]
    return v


def _is_sig(s: str) -> bool:
    return bool(s) and all(c in "ybnqiuxtdsogavh(){}" for c in s)


def props(bus: str, service: str, path: str, iface: str) -> dict:
    r = call(bus, service, path, "org.freedesktop.DBus.Properties", "GetAll", "s", (iface,))
    u = unwrap(r) if isinstance(r, dict) else None
    return u if isinstance(u, dict) else {}


def prop(bus: str, service: str, path: str, iface: str, name: str):
    r = call(bus, service, path, "org.freedesktop.DBus.Properties", "Get", "ss", (iface, name))
    return None if r is None else unwrap(r)


def set_prop(bus: str, service: str, path: str, iface: str, name: str, sig: str, value) -> bool:
    r = call(bus, service, path, "org.freedesktop.DBus.Properties", "Set", "ssv", (iface, name, (sig, value)))
    return r is not None
