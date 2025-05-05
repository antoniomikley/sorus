{
  "${onboarding_ip_v4}" = {pkgs,lib,config,...}: {

    system.stateVersion = "24.11";

    deployment.secrets = {
      "sops-file" = {
        source = "/tmp/onboarding/${new_host_name}/default_sops.yaml";
        destination = "/etc/nixos/secrets/default_sops.yaml";
        owner.user = "root";
        owner.group = "root";
        permissions = "0644";
      };
    };

    sops = {
      defaultSopsFile = "/etc/nixos/secrets/default_sops.yaml";
      validateSopsFiles = false;
      age = {
        generateKey = true;
        sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      };
      secrets = {
        tech_user_pw = {
          neededForUsers = true;
        };
        wg_private_key = {
          owner = "systemd-network";
          mode = "0700";
        };
      };
    };

    imports =  [
      "${builtins.fetchTarball {
        url = "https://github.com/Mic92/sops-nix/archive/67566fe68a8bed2a7b1175fdfb0697ed22ae8852.tar.gz";
        sha256 = "10sb004jfr0gccj7q9znfk4h23bbzv5s0q1kg6cxf19f7d86jsb4";
      }}/modules/sops"
      ./hardware-configuration.nix
    ];
    
    nixpkgs.overlays = [
      (self: super: {serf-agent-bin = super.callPackage ./serf-agent-bin.nix{};})
    ];

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    users = {
      mutableUsers = false;
      users.tech_user = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        hashedPasswordFile = config.sops.secrets.tech_user_pw.path;
        packages = with pkgs; [
        ];
      };
    };

    users.users.emergency = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      password = "Install123!";
      packages = with pkgs; [
      ];
    };

    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      vim
        wget
        wireguard-tools
        tmux
        serf-agent-bin
    ];

    boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    programs.mtr.enable = true;
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    services.openssh = {
      enable = true;
      openFirewall = true;
    };

    networking = {
      useDHCP = false;
      hostName = "${new_host_name}";
      firewall = {
        allowedTCPPorts = [ 7373 7946 42069 ]; 
      };
    };

    systemd = {
      network = {
        enable = true;
        netdevs = {
          "10-wg0" = {
            netdevConfig = {
              Kind = "wireguard";
              Name = "wg0";
              MTUBytes = "1300";
            };
            wireguardConfig = {
              PrivateKeyFile = config.sops.secrets.wg_private_key.path;
              ListenPort = 9918;
            };
	    wireguardPeers = [
	      {
                PublicKey = "${wg_server_pub_key}";
                AllowedIPs = [ "0.0.0.0/0" ];
                Endpoint = "[${wg_server_ip_v6}]:51820";
	      }
            ];
          };
        };
        networks = {
          "10-wan" = {
            matchConfig.Name = "enp1s0";
            networkConfig = {
              DHCP = "ipv4";
              IPv6AcceptRA = true;
              IPMasquerade = "both";
            };
            dhcpV4Config.ClientIdentifier = "mac";
          };
          "20-wg0" = {
            matchConfig.Name = "wg0";
            address = [ "${wg_client_ip_v4}/24" ];
            DHCP = "no";
            gateway = [ "10.0.0.1" ];
            networkConfig = {
              IPv6AcceptRA = false;
            };
          };
        };
      };
      services = {
        "serf-agent" = {
          wantedBy = ["multi-user.target"];
          bindsTo = ["sys-subsystem-net-devices-wg0.device"];
          after = ["sys-subsystem-net-devices-wg0.device"];
          wants = ["serf-join.service"];
          description = "Hashicorp SERF agent";
          serviceConfig = {
            Type = "simple";
            User = "root";
            ExecStart = "${pkgs.serf-agent-bin}/bin/serf agent -node ${new_host_name} -bind ${wg_client_ip_v4}";
          };
        };
        "serf-join" = {
          wantedBy = ["multi-user.target"];
          after = ["serf-agent.service"];
          description = "Join Serf Cluster";
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            ExecStart = "${pkgs.serf-agent-bin}/bin/serf join 10.0.0.1";
            Restart = "on-failure";
          };
        };
      };
    };
  };
}
