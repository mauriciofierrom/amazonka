# The build system where packages will be built.
{ system ? builtins.currentSystem
  # The host system where packages will run.
, crossSystem ? null
  # Additional sources.json overrides.
, sources ? { }
  # Additional nixpkgs.config overrides.
, config ? { }
  # Additional nixpkgs.overlays.
, overlays ? [ ]
  # Overlays to apply to the last package set in cross compilation.
, crossOverlays ? [ ]
  # The names of the models to generate - ie. [ "ec2", "s3" ]
  # Setting to null will use file names from ./config
, models ? null
}:

let

  pkgs = import ./nix/default.nix {
    inherit system sources config overlays crossOverlays;
  };

  inherit (pkgs) libLocal cabalProject tools;

  botocore = pkgs.sources.botocore;
  botocoreData = "${botocore}/botocore/data";
  botocoreRev = builtins.substring 0 7 botocore.rev;

  annexDir = ./config/annexes;
  configDir = ./config/models;
  templateDir = ./config/templates;
  staticDir = ./config/static;

  clientVersion = cabalProject.amazonka.identifier.version;
  coreVersion = cabalProject.amazonka-core.identifier.version;
  libraryVersion = cabalProject.amazonka-gen.identifier.version;

  modelNamesFromDir = path:
    builtins.map (pkgs.lib.strings.removeSuffix ".json")
    (builtins.attrNames (builtins.readDir path));

  modelNames = if models == null then modelNamesFromDir configDir else models;

  modelArguments = builtins.concatStringsSep " "
    (builtins.map (v: ''--model="${botocoreData + "/${v}"}"'') modelNames);

in pkgs.stdenvNoCC.mkDerivation {
  pname = "amazonka";
  version = botocoreRev;
  phases = [ "generatePhase" "formatPhase" "fixupPhase" ];

  buildInputs = [
    tools.cabal-fmt
    tools.ormolu
    cabalProject.amazonka-gen.components.exes.amazonka-gen
  ];

  src = libLocal.cleanGeneratedSource {
    name = "amazonka-generate";
    src = ./lib;
  };

  generatePhase = ''
    echo "Copying sources"

    mkdir -p $out
    cp -R $src/amazonka-* $out/
    chmod -R u+rw $out

    amazonka-gen \
      --out=$out \
      --library-version=${libraryVersion} \
      --client-version=${clientVersion} \
      --core-version=${coreVersion} \
      --annexes="${annexDir}" \
      --configs="${configDir}" \
      --templates="${templateDir}" \
      --static="${staticDir}" \
      --retry=${botocoreData}/_retry.json \
      ${modelArguments}
  '';

  formatPhase = ''
    export LC_ALL=C.UTF-8

    cd $out

    for dir in amazonka*; do 
      echo " -> Formatting $dir"

      find $dir -type f -name '*.cabal' -print0 \
        | xargs -0 cabal-fmt --inplace --indent=2

      find $dir -type f -name '*.hs' -print0 \
        | xargs -0 ormolu --mode=inplace
    done
  '';
}
