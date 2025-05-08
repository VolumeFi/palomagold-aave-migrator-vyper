from ape import accounts, project, networks


def main():
    acct = accounts.load("deployer_account")
    compass = "0x3c1864a873879139C1BD87c7D95c4e475A91d19C"
    weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
    router = "0x2191718CD32d02B8E60BAdFFeA33E4B5DD9A0A0D"
    pool = "0x794a61358D6845594F94dc1DB02A252b5b4814aD"
    usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
    pagld = "0x3f146767AeC2F10484210a6525a807F8eA68613d"
    gold_wallet = "0x22a017ec45ea1ae0b43b1aa55f50fffe1da468ec"
    refund_wallet = "0x6dc0A87638CD75Cc700cCdB226c7ab6C054bc70b"
    gas_fee = 3_000_000_000_000_000  # 10$
    service_fee_collector = "0xe693603C9441f0e645Af6A5898b76a60dbf757F4"
    service_fee = 2_500_000_000_000_000  # 0.25%
    priority_fee = int(networks.active_provider.priority_fee)
    base_fee = int(networks.active_provider.base_fee * 1.2 + priority_fee)
    migrator = project.migrator.deploy(
        compass, weth, router, pool, usdc, pagld, gold_wallet, refund_wallet, gas_fee,
        service_fee_collector, service_fee, max_fee = base_fee, max_priority_fee=priority_fee, sender=acct)

    print(migrator)

# 0x86B4260727FF6F50a21660B7A09B7905022c8675
