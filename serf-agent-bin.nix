{ buildGoModule, fetchFromGitHub }:
buildGoModule rec {
  pname = "serf-agent";
  version = "0.10.2";
  src = fetchFromGitHub {
    owner = "hashicorp";
    repo = "serf";
    rev = "v${version}";
    hash = "sha256-8kMQu3UYGihlYW7rdh1IkvRR/FgFK/N+iay0y6qOOWE=";
  };
  vendorHash = "sha256-aNAbE8yFp8HUgdRtt/3eVz4VAaqSTPB4XKKLl1o7YRc=";
  doCheck = false;
}
