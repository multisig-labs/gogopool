# Foundry Tests

All tests should inherit from BaseTest.sol, which has a setUp() func that constructs all major necessary contracts and ties them together and initializes as needed. If your test contract wants to do something special, it can have it's own setup func:

```
	function setUp() public override {
		super.setUp();
		// Your custom logic here
	}

	function setUp() public override {
		// Or don't call super and have your own custom logic
	}

```
