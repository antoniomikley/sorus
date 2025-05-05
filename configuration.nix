{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    "${builtins.fetchTarball {
      url = "https://github.com/Mic92/sops-nix/archive/67566fe68a8bed2a7b1175fdfb0697ed22ae8852.tar.gz";
      sha256 = "10sb004jfr0gccj7q9znfk4h23bbzv5s0q1kg6cxf19f7d86jsb4";
    }}/modules/sops"
  ];

  nixpkgs.overlays = [
    (self: super: {serf-agent-bin = super.callPackage ./serf-agent-bin.nix {};})
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";

  sops = {
    defaultSopsFile = ./default_sops.yaml;
    age = {
      sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
      generateKey = true;
    };
    secrets = {
      wireguard_private_key = {
        owner = "systemd-network";
        mode = "0700";
      };
      mother_hashed_pw = {
        neededForUsers = true;
      };
    };
  };

  users.mutableUsers = false;
  users.users.mother = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.mother_hashed_pw.path;
    packages = with pkgs; [
    ];
  };

  security.sudo.wheelNeedsPassword = false;
  
  environment.systemPackages = with pkgs; [
    vim
    git
    gh
    wget
    wireguard-tools
    tmux
    morph
    serf-agent-bin
    ipcalc
    jq
    sops
    ssh-to-age
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
  };

  systemd = {
    services = {
      "serf-agent" = {
        wantedBy = [ "multi-user.target" ];
        after = ["network.target"];
        description = "Hashicorp SERF agent";
        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStart = "${pkgs.serf-agent-bin}/bin/serf agent -bind 10.0.0.1";
        };
      };
    };
    network = {
      enable = true;
      netdevs = {
        "50-wg0" = {
          netdevConfig = {
            Kind = "wireguard";
            Name = "wg0";
            MTUBytes = "1300";
          };
          wireguardConfig = {
            PrivateKeyFile = config.sops.secrets.wireguard_private_key.path;
            ListenPort = 51820;
          };
          wireguardPeers = (lib.lists.forEach (lib.attrsets.mapAttrsToList (name: value: name) (builtins.readDir ./wg-peers)) (file: import (./. + "/wg-peers/${file}")));
        };
      };
      networks = {
        "10-wan" = {
          matchConfig.Name = "enp1s0";
          networkConfig = {
            IPv6AcceptRA = true;
            DHCP = "ipv4";
          };
        };
        "wg0" = {
          matchConfig.Name = "wg0";
          address = ["10.0.0.1/24"];
          networkConfig = {
            IPMasquerade = "both";
          };
        };
      };
    };
  };
  networking = {
    hostName = "nixos-mother";
    useDHCP = false;
    firewall = {
      allowedTCPPorts = [ 7946 42069 ];
      allowedUDPPorts = [ 51820 ];
#     enable = false;
    };
  };

  system.stateVersion = "24.11";
}

