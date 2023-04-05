Welcome to the scenarios. Happy to have you.

Here you will find a collection of hardhat tasks designed to put the system through it's paces.

Why isn't this just a test? Great question and thanks for asking.
It's more interactive than a test. If you want to know how something works change the parameters and see the output in real time.

We also have tests written in Solidity: `/test`

View the state of the system with [Panopticon](https://panopticon.fly.dev/home), and select Hardhat from the dropdown top right.

Here are some commands that also show system state

```sh
just task debug:list_actor_balances
just task debug:list_vars
just task minipool:list
```

We have pre-defined actors we use in these tests: alice, bob, nodeOp1, rialto1...
You can see them all with

```sh
just task debug:list_actor_balances
just task debug:output_named_users
```

View all contracts with

```sh
just task debug:list_contract
```

Tokens

It's all in `tokens.js` but a few especially useful ones are

```sh
just task ggp:deal --recip alice --amt 1000
```

Shortcomings.
We don't have a great way to specify a user that's not one of the named users, i.e. by providing your own private key.

You can modify a task and use the private key with

```
const signer = new ethers.Wallet(
  "private_key_goes_here",
  hre.ethers.provider
);
```
