# nix-bitcoin security fund

The nix-bitcoin security fund is a collection of funds held on the following 2/3
bitcoin multisig address which is used to reward security researchers who
discover and report vulnerabilities in nix-bitcoin or its upstream dependencies.
Rewards are paid out as percentages of the total fund, rather than as fixed
amounts.

```
bc1qrpnz05n0yznaj6yw82wy8dhwuqz86s87vdlhq4cu92fus9qal25s555wsy
```

The following nix-bitcoin developers each hold one key to the multisig address
and collectively form the nix-bitcoin developer quorum:

- Jonas Nick (0xB1A70E4F8DCD0366) [@nickler:nixbitcoin.org](https://matrix.to/#/@nickler:nixbitcoin.org)
- Erik Arvstedt (0x33312B944DD97846) [@erikarvstedt:matrix.org](https://matrix.to/#/@erikarvstedt:matrix.org)
- nixbitcoindev (0xDD11F9AD5308B3BA) [@nixbitcoindev:nixbitcoin.org](https://matrix.to/#/@nixbitcoindev:nixbitcoin.org)

## Eligible Vulnerabilities

The following types of vulnerabilities qualify for rewards, to the
exclusion of all other security vulnerabilities.

| Type | Description | Examples |
| :-: | :-: | :-: |
| Outright Vulnerabilities | Vulnerabilities in nix-bitcoin specific tooling (except CI tooling) | privilege escalation in SUID binary `netns-exec`, improper release signature verification through `fetch-release` |
| Violations of [PoLP](https://en.wikipedia.org/wiki/Principle_of_least_privilege) | nix-bitcoin services are given too much privilege over the system or unnecessary access to other nix-bitcoin services, or one of the nix-bitcoin isolation measures is incorrectly implemented | `netns-isolation` doesn't work, spark-wallet has access to bitcoin RPC interface or files |
| Vulnerabilities in Dependencies | A vulnerability in any dependency of a nix-bitcoin installation with a configuration consisting of any combination of the following services: bitcoind, clightning (plugins not included), lnd, electrs, joinmarket, btcpayserver, liquidd | Compromised NixOS expression pulls in malicious package, JoinMarket pulls in a python dependency with a known severe vulnerability |
| Bad Documentation | Our documentation suggests blatantly insecure things | `install.md` tells you to add our ssh keys to your root user |
| Compromise of Signing Key | Compromise of the nix-bitcoin signing key, i.e., `0xB1A70E4F8DCD0366` | Leaking the key, managing to sign something with it |

## Reward

Researchers qualify for a maximum reward of 10% of the total fund holdings \* for
reporting any vulnerability that matches the above eligibility requirements. If
a vulnerability or any combination of a number of vulnerabilities that meet the
above-described eligibility requirements can lead to a realistic attack
on nix-bitcoin users, researchers qualify for a higher
maximum reward\* depending the final outcome of the attack scenario:

| Outcome | Description | Maximum Reward of Total Fund \* |
| :-: | :-: | :-: |
| Loss of Funds | attack allows stealing or destroying user's funds | 50 % |
| Loss of Privacy | attack allows exfiltrating sensitive information or otherwise attributing a user's real world identity to his nix-bitcoin node or funds held/managed thereon without the user specifically opting-in to this (e.g., by disabling the `secure-node` preset) | 25 % |
| Denial of Service | attack allows crashing a service or otherwise denying a user service from his node | 25 % |

All other reported vulnerabilities which meet the above requirements without a
clear and plausible attack scenario receive a maximum reward\* of 10% of the
fund.

\* Rewards are subject to a discount at the sole discretion
of the nix-bitcoin developer quorum for reasons such as insignificance of the vulnerability or
obscurity of the victim's required configuration, as well as simple mitigation (i.e.
the attack should have been mitigated anyway by common-sense security measures)
or complex/unlikely attack execution.

## Policy

* Reponsible Disclosure: Vulnerabilities must be [responsibly
  disclosed](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure)
* E2EE: Vulnerabilities must be disclosed via end-to-end encrypted communication
  methods, such as PGP E-Mail or Matrix
* First come, first serve: Rewards are awarded strictly on a first come, first
  serve basis from the date they were responsibly disclosed in their entirety.
  Multiple reports from the same researcher can either be bundled for a higher
  likelihood of receiving the full maximum reward or rewarded
  proportional to the remaining amount individually.
* Exclusion of dependencies with existing bug bounty programms: Software which
  is covered by an existing bug bounty program is not eligible for reward under
  the "Vulnerabilities in Dependencies" vulnerability type of the nix-bitcoin
  security fund
* Exclusion of dependencies with known vulnerabilities that are in the process
  of being patched: Software with a known vulnerability where there is reason to
  believe that the patch is still under development or simply has not yet been
  ported to NixOS, due to the relative recency of the patch, is not eligible for
  reward under the "Vulnerabilities in Dependencies" vulnerability type of the
  nix-bitcoin security fund
* Termination: The fund can be terminated at any time by the quorum of key
  holders in which case the holdings are donated to non-profit organizations.
* The fund's holdings can be used for purposes not mentioned in this
  document.

## Wall of Fame

In addition to the above rewards, security researchers will also be added
to this Wall of Fame, unless, of course, they wish to remain anonymous.
