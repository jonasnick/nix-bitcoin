from collections import OrderedDict
import json
import re

def succeed(*cmds):
    """Returns the concatenated output of all cmds"""
    return machine.succeed(*cmds)

def assert_matches(cmd, regexp):
    out = succeed(cmd)
    if not re.search(regexp, out):
        raise Exception(f"Pattern '{regexp}' not found in '{out}'")

def assert_full_match(cmd, regexp):
    out = succeed(cmd)
    if not re.fullmatch(regexp, out):
        raise Exception(f"Pattern '{regexp}' doesn't match '{out}'")

def log_has_string(unit, str):
    return f"journalctl -b --output=cat -u {unit} --grep='{str}'"

def assert_no_failure(unit):
    """Unit should not have failed since the system is running"""
    machine.fail(log_has_string(unit, "Failed with result"))

def assert_running(unit):
    with machine.nested(f"waiting for unit: {unit}"):
        machine.wait_for_unit(unit)
    assert_no_failure(unit)

def wait_for_open_port(address, port):
    def is_port_open(_):
        status, _ = machine.execute(f"nc -z {address} {port}")
        return status == 0

    with machine.nested(f"Waiting for TCP port {address}:{port}"):
        retry(is_port_open)


### Test runner

tests = OrderedDict()

def test(name):
    def x(fn):
        tests[name] = fn
    return x

def run_tests():
    enabled = enabled_tests.copy()
    to_run = []
    for test in tests:
        if test in enabled:
            enabled.remove(test)
            to_run.append(test)
    if enabled:
        raise RuntimeError(f"The following tests are enabled but not defined: {enabled}")
    machine.connect()  # Visually separate boot output from the test output
    for test in to_run:
        with machine.nested(f"test: {test}"):
            tests[test]()

def run_test(test):
    tests[test]()


### Tests
# All tests are executed in the order they are defined here

@test("security")
def _():
    assert_running("setup-secrets")
    # Unused secrets should be inaccessible
    succeed('[[ $(stat -c "%U:%G %a" /secrets/dummy) = "root:root 440" ]]')

    if "secure-node" in enabled_tests:
        machine.wait_for_unit("bitcoind")
        # `systemctl status` run by unprivileged users shouldn't leak cgroup info
        assert_matches(
            "runuser -u electrs -- systemctl status bitcoind 2>&1 >/dev/null",
            "Failed to dump process list for 'bitcoind.service', ignoring: Access denied",
        )
        # The 'operator' with group 'proc' has full access
        assert_full_match("runuser -u operator -- systemctl status bitcoind 2>&1 >/dev/null", "")

@test("bitcoind")
def _():
    assert_running("bitcoind")
    machine.wait_until_succeeds("bitcoin-cli getnetworkinfo")
    assert_matches("runuser -u operator -- bitcoin-cli getnetworkinfo | jq", '"version"')

    regtest = "regtest/" if "regtest" in enabled_tests else ""
    assert_full_match(f"stat  -c '%a' /var/lib/bitcoind/{regtest}.cookie", "640\n")

    # RPC access for user 'public' should be restricted
    machine.fail(
        "bitcoin-cli -rpcuser=public -rpcpassword=$(cat /secrets/bitcoin-rpcpassword-public) stop"
    )
    machine.wait_until_succeeds(
        log_has_string("bitcoind", "RPC User public not allowed to call method stop")
    )

@test("electrs")
def _():
    assert_running("electrs")
    wait_for_open_port(ip("electrs"), 4224)  # prometeus metrics provider
    # Check RPC connection to bitcoind
    if not "regtest" in enabled_tests:
        machine.wait_until_succeeds(
            log_has_string("electrs", "waiting for 0 blocks to download")
        )

# Impure: Stops electrs
# Stop electrs from spamming the test log with 'waiting for 0 blocks to download' messages
@test("stop-electrs")
def _():
    succeed("systemctl stop electrs")

@test("liquidd")
def _():
    assert_running("liquidd")
    machine.wait_until_succeeds("elements-cli getnetworkinfo")
    assert_matches("runuser -u operator -- elements-cli getnetworkinfo | jq", '"version"')
    succeed("runuser -u operator -- liquidswap-cli --help")

@test("clightning")
def _():
    assert_running("clightning")
    assert_matches("runuser -u operator -- lightning-cli getinfo | jq", '"id"')

    if test_data["clightning-replication"]:
        assert_running("clightning-replication-mounts")
        replica_db = "/var/lib/clightning-replication/plaintext/lightningd.sqlite3"
        succeed(f"runuser -u clightning -- ls {replica_db}")
        # No other user should be able to read the unencrypted files
        machine.fail(f"runuser -u bitcoin -- ls {replica_db}")
        succeed("runuser -u clightning -- gocryptfs -info /var/backup/clightning/lightningd-db/")

    if test_data["clightning-plugins"]:
        plugin_list = succeed("lightning-cli plugin list")
        plugins = json.loads(plugin_list)["plugins"]
        active = set(plugin["name"] for plugin in plugins if plugin["active"])
        failed = set(test_data["clightning-plugins"]).difference(active)
        if failed:
            raise Exception(
                f"The following clightning plugins are inactive:\n{failed}.\n\n"
                f"Output of 'lightning-cli plugin list':\n{plugin_list}"
            )
        else:
            machine.log("Active clightning plugins:")
            for p in test_data["clightning-plugins"]:
                machine.log(os.path.basename(p))

@test("lnd")
def _():
    assert_running("lnd")
    assert_matches("runuser -u operator -- lncli getinfo | jq", '"version"')
    assert_no_failure("lnd")

@test("lndconnect-onion-lnd")
def _():
    assert_running("lnd")
    assert_matches("runuser -u operator -- lndconnect-onion --url", ".onion")

@test("lndconnect-onion-clightning")
def _():
    assert_running("clightning-rest")
    assert_matches("runuser -u operator -- lndconnect-onion-clightning --url", ".onion")

@test("lightning-loop")
def _():
    assert_running("lightning-loop")
    assert_matches("runuser -u operator -- loop --version", "version")
    # Check that lightning-loop fails with the right error, making sure
    # lightning-loop can connect to lnd
    machine.wait_until_succeeds(
        log_has_string(
            "lightning-loop",
            "Waiting for lnd to be fully synced to its chain backend, this might take a while",
        )
    )

@test("lightning-pool")
def _():
    assert_running("lightning-pool")
    assert_matches("su operator -c 'pool --version'", "version")
    # Check that lightning-pool fails with the right error, making sure
    # lightning-pool can connect to lnd
    machine.wait_until_succeeds(
        log_has_string(
            "lightning-pool",
            "Waiting for lnd to be fully synced to its chain backend, this might take a while",
        )
    )

@test("charge-lnd")
def _():
    # charge-lnd is a oneshot service that is started by a timer under regular operation
    succeed("systemctl start charge-lnd")
    assert_no_failure("charge-lnd")

@test("btcpayserver")
def _():
    assert_running("nbxplorer")
    machine.wait_until_succeeds(log_has_string("nbxplorer", "BTC: RPC connection successful"))
    if test_data["btcpayserver-lbtc"]:
        machine.wait_until_succeeds(log_has_string("nbxplorer", "LBTC: RPC connection successful"))
    wait_for_open_port(ip("nbxplorer"), 24444)

    assert_running("btcpayserver")
    machine.wait_until_succeeds(log_has_string("btcpayserver", "Now listening on"))
    wait_for_open_port(ip("btcpayserver"), 23000)
    # test lnd custom macaroon
    assert_matches(
        "runuser -u btcpayserver -- curl -fsS --cacert /secrets/lnd-cert "
        '--header "Grpc-Metadata-macaroon: $(xxd -ps -u -c 1000 /run/lnd/btcpayserver.macaroon)" '
        f"-X GET https://{ip('lnd')}:8080/v1/getinfo | jq",
        '"version"',
    )
    # Test web server response
    assert_matches(f"curl -fsS -L {ip('btcpayserver')}:23000", "Welcome to your BTCPay&nbsp;Server")

@test("rtl")
def _():
    assert_running("rtl")
    machine.wait_until_succeeds(
        log_has_string("rtl", "Server is up and running")
    )

@test("clightning-rest")
def _():
    assert_running("clightning-rest")
    machine.wait_until_succeeds(
        log_has_string("clightning-rest", "cl-rest api server is ready and listening on port: 3001")
    )

@test("spark-wallet")
def _():
    assert_running("spark-wallet")
    wait_for_open_port(ip("spark-wallet"), 9737)
    spark_auth = re.search("login=(.*)", succeed("cat /secrets/spark-wallet-login"))[1]
    assert_matches(f"curl -fsS {spark_auth}@{ip('spark-wallet')}:9737", "Spark")

@test("joinmarket")
def _():
    assert_running("joinmarket")
    machine.wait_until_succeeds(
        log_has_string("joinmarket", "JMDaemonServerProtocolFactory starting on 27183")
    )

@test("joinmarket-yieldgenerator")
def _():
    if "regtest" in enabled_tests:
        expected_log_msg = "You do not have the minimum required amount of coins to be a maker"
    else:
        expected_log_msg = "Critical error updating blockheight."

    machine.wait_until_succeeds(log_has_string("joinmarket-yieldgenerator", expected_log_msg))

@test("joinmarket-ob-watcher")
def _():
    assert_running("joinmarket-ob-watcher")
    machine.wait_until_succeeds(log_has_string("joinmarket-ob-watcher", "Starting ob-watcher"))

@test("nodeinfo")
def _():
    status, _ = machine.execute("systemctl is-enabled --quiet onion-addresses 2> /dev/null")
    if status == 0:
        machine.wait_for_unit("onion-addresses")
    json_info = succeed("runuser -u operator -- nodeinfo")
    info = json.loads(json_info)
    assert info["bitcoind"]["local_address"]

@test("secure-node")
def _():
    assert_running("onion-addresses")

# Run this test before the following tests that shut down services
# (and their corresponding network namespaces).
@test("netns-isolation")
def _():
    def get_ips(services):
        enabled = enabled_tests.intersection(services)
        return " ".join(ip(service) for service in enabled)

    def assert_reachable(src, dests):
        dest_ips = get_ips(dests)
        if src in enabled_tests and dest_ips:
            machine.succeed(f"ip netns exec nb-{src} fping -c1 -t100 {dest_ips}")

    def assert_unreachable(src, dests):
        dest_ips = get_ips(dests)
        if src in enabled_tests and dest_ips:
            machine.fail(
                # This fails when no host is reachable within 100 ms
                f"ip netns exec nb-{src} fping -c1 -t100 --reachable=1 {dest_ips}"
            )

    # These reachability tests are non-exhaustive
    assert_reachable("bitcoind", ["clightning", "lnd", "liquidd"])
    assert_unreachable("bitcoind", ["btcpayserver", "spark-wallet", "lightning-loop"])
    assert_unreachable("btcpayserver", ["bitcoind", "lightning-loop"])

    # netns addresses can not be bound to in the main netns.
    # This prevents processes in the main netns from impersonating nix-bitcoin services.
    assert_matches(
        f"nc -l {ip('bitcoind')} 1080 2>&1 || true", "nc: Cannot assign requested address"
    )

    if "joinmarket" in enabled_tests:
        # netns-exec should drop capabilities
        assert_matches(
            "runuser -u operator -- netns-exec nb-joinmarket capsh --print | grep Current",
            re.compile("^Current: =$", re.MULTILINE),
        )

    if "clightning" in enabled_tests:
        # netns-exec should fail for unauthorized namespaces
        machine.fail("netns-exec nb-clightning ip a")

        # netns-exec should only be executable by the operator user
        machine.fail("runuser -u clightning -- netns-exec nb-bitcoind ip a")


# Impure: stops bitcoind (and dependent services)
@test("backups")
def _():
    # For testing that bitcoind wallets are backed up
    succeed("bitcoin-cli -named createwallet wallet_name=test blank=true >/dev/null")

    succeed("systemctl stop bitcoind")
    succeed("systemctl start duplicity")
    machine.wait_until_succeeds(log_has_string("duplicity", "duplicity.service: Deactivated successfully."))
    run_duplicity = "export $(cat /secrets/backup-encryption-env); duplicity"
    # Files in backup and /var/lib should be identical
    assert_matches(
        f"{run_duplicity} verify --archive-dir /var/lib/duplicity file:///var/lib/localBackups /var/lib",
        "0 differences found",
    )
    # Backup should include important files
    files = {
        "bitcoind": "var/lib/bitcoind/test/wallet.dat",
        "clightning": "var/lib/clightning/bitcoin/hsm_secret",
        "lnd": "var/lib/lnd/lnd-seed-mnemonic",
        "joinmarket": "var/lib/joinmarket/jm-wallet-seed",
        "btcpayserver": "var/backup/postgresql/btcpaydb.sql.gz",
    }
    actual_files = succeed(f"{run_duplicity} list-current-files file:///var/lib/localBackups")

    def assert_file_exists(file):
        if file not in actual_files:
            raise Exception(f"Backup file '{file}' is missing.")

    for test, file in files.items():
        if test in enabled_tests:
            assert_file_exists(file)

    assert_file_exists("secrets/lnd-wallet-password")

# Impure: restarts services
@test("banlist-and-restart")
def _():
    machine.wait_until_succeeds(log_has_string("bitcoind-import-banlist", "Importing node banlist"))
    assert_no_failure("bitcoind-import-banlist")

    # Current time in µs
    pre_restart = succeed("date +%s.%6N").rstrip()

    # Sanity-check system by restarting bitcoind.
    # This also restarts all services depending on bitcoind.
    succeed("systemctl restart bitcoind")

    # Now that the bitcoind restart triggered a banlist import restart, check that
    # re-importing already banned addresses works
    machine.wait_until_succeeds(
        log_has_string(f"bitcoind-import-banlist --since=@{pre_restart}", "Importing node banlist")
    )
    assert_no_failure("bitcoind-import-banlist")

@test("regtest")
def _():
    def enabled(unit):
        if unit in enabled_tests:
            # Wait because the unit might have been restarted in the preceding
            # 'banlist-and-restart' test
            machine.wait_for_unit(unit)
            return True
        else:
            return False

    num_blocks = test_data["num_blocks"]

    if enabled("electrs"):
        machine.wait_until_succeeds(log_has_string("electrs", "serving Electrum RPC"))
        get_block_height_cmd = (
            """echo '{"method": "blockchain.headers.subscribe", "id": 0, "params": []}'"""
            f" | nc {ip('electrs')} 50001 | head -1 | jq -M .result.height"
        )
        assert_full_match(get_block_height_cmd, f"{num_blocks}\n")
    if enabled("clightning"):
        machine.wait_until_succeeds(
            f"[[ $(runuser -u operator -- lightning-cli getinfo | jq -M .blockheight) == {num_blocks} ]]"
        )
    if enabled("lnd"):
        machine.wait_until_succeeds(
            f"[[ $(runuser -u operator -- lncli getinfo | jq -M .block_height) == {num_blocks} ]]"
        )
    if enabled("lightning-loop"):
        machine.wait_until_succeeds(
            log_has_string("lightning-loop", f"Starting event loop at height {num_blocks}")
        )
        succeed("runuser -u operator -- loop getparams")
    if enabled("lightning-pool"):
        machine.wait_until_succeeds(
            log_has_string("lightning-pool", "lnd is now fully synced to its chain backend")
        )
        succeed("runuser -u operator -- pool orders list")
    if enabled("btcpayserver"):
        machine.wait_until_succeeds(log_has_string("nbxplorer", f"At height: {num_blocks}"))

if "netns-isolation" in enabled_tests:
    def ip(name):
        return test_data["netns"][name]["address"]
else:
    def ip(_):
        return "127.0.0.1"
