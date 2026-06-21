{ ... }:

{
  inputs.plasmazones = {
    url = "github:fuddlesworth/PlasmaZones";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      {
        imports = [ inputs.plasmazones.nixosModules.default ];
        programs.plasmazones.enable = true;
      }
    ];

  meta.name = "plasmazones";
}
