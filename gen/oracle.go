// Code generated - DO NOT EDIT.
// This file is a generated binding and any manual changes will be lost.

package oracle

import (
	"errors"
	"math/big"
	"strings"

	"github.com/ava-labs/coreth/accounts/abi"
	"github.com/ava-labs/coreth/accounts/abi/bind"
	"github.com/ava-labs/coreth/core/types"
	"github.com/ava-labs/coreth/interfaces"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/event"
)

// Reference imports to suppress errors if they are not otherwise used.
var (
	_ = errors.New
	_ = big.NewInt
	_ = strings.NewReader
	_ = interfaces.NotFound
	_ = bind.Bind
	_ = common.Big1
	_ = types.BloomLookup
	_ = event.NewSubscription
)

// OracleMetaData contains all meta data concerning the Oracle contract.
var OracleMetaData = &bind.MetaData{
	ABI: "[{\"inputs\":[{\"internalType\":\"contractStorage\",\"name\":\"storageAddress\",\"type\":\"address\"}],\"stateMutability\":\"nonpayable\",\"type\":\"constructor\"},{\"inputs\":[],\"name\":\"ContractNotFound\",\"type\":\"error\"},{\"inputs\":[],\"name\":\"ContractPaused\",\"type\":\"error\"},{\"inputs\":[],\"name\":\"InvalidGGPPrice\",\"type\":\"error\"},{\"inputs\":[],\"name\":\"InvalidOrOutdatedContract\",\"type\":\"error\"},{\"inputs\":[],\"name\":\"InvalidTimestamp\",\"type\":\"error\"},{\"inputs\":[],\"name\":\"MustBeGuardian\",\"type\":\"error\"},{\"inputs\":[],\"name\":\"MustBeGuardianOrValidContract\",\"type\":\"error\"},{\"inputs\":[],\"name\":\"MustBeMultisig\",\"type\":\"error\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint256\",\"name\":\"price\",\"type\":\"uint256\"},{\"indexed\":false,\"internalType\":\"uint256\",\"name\":\"timestamp\",\"type\":\"uint256\"}],\"name\":\"GGPPriceUpdated\",\"type\":\"event\"},{\"inputs\":[{\"internalType\":\"string\",\"name\":\"contractName\",\"type\":\"string\"}],\"name\":\"getContractAddress\",\"outputs\":[{\"internalType\":\"address\",\"name\":\"\",\"type\":\"address\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"getGGPPriceInAVAX\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"price\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"timestamp\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"getGGPPriceInAVAXFromOneInch\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"price\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"timestamp\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"price\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"timestamp\",\"type\":\"uint256\"}],\"name\":\"setGGPPriceInAVAX\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"address\",\"name\":\"addr\",\"type\":\"address\"}],\"name\":\"setOneInch\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"version\",\"outputs\":[{\"internalType\":\"uint8\",\"name\":\"\",\"type\":\"uint8\"}],\"stateMutability\":\"view\",\"type\":\"function\"}]",
}

// OracleABI is the input ABI used to generate the binding from.
// Deprecated: Use OracleMetaData.ABI instead.
var OracleABI = OracleMetaData.ABI

// Oracle is an auto generated Go binding around an Ethereum contract.
type Oracle struct {
	OracleCaller     // Read-only binding to the contract
	OracleTransactor // Write-only binding to the contract
	OracleFilterer   // Log filterer for contract events
}

// OracleCaller is an auto generated read-only Go binding around an Ethereum contract.
type OracleCaller struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// OracleTransactor is an auto generated write-only Go binding around an Ethereum contract.
type OracleTransactor struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// OracleFilterer is an auto generated log filtering Go binding around an Ethereum contract events.
type OracleFilterer struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// OracleSession is an auto generated Go binding around an Ethereum contract,
// with pre-set call and transact options.
type OracleSession struct {
	Contract     *Oracle           // Generic contract binding to set the session for
	CallOpts     bind.CallOpts     // Call options to use throughout this session
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// OracleCallerSession is an auto generated read-only Go binding around an Ethereum contract,
// with pre-set call options.
type OracleCallerSession struct {
	Contract *OracleCaller // Generic contract caller binding to set the session for
	CallOpts bind.CallOpts // Call options to use throughout this session
}

// OracleTransactorSession is an auto generated write-only Go binding around an Ethereum contract,
// with pre-set transact options.
type OracleTransactorSession struct {
	Contract     *OracleTransactor // Generic contract transactor binding to set the session for
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// OracleRaw is an auto generated low-level Go binding around an Ethereum contract.
type OracleRaw struct {
	Contract *Oracle // Generic contract binding to access the raw methods on
}

// OracleCallerRaw is an auto generated low-level read-only Go binding around an Ethereum contract.
type OracleCallerRaw struct {
	Contract *OracleCaller // Generic read-only contract binding to access the raw methods on
}

// OracleTransactorRaw is an auto generated low-level write-only Go binding around an Ethereum contract.
type OracleTransactorRaw struct {
	Contract *OracleTransactor // Generic write-only contract binding to access the raw methods on
}

// NewOracle creates a new instance of Oracle, bound to a specific deployed contract.
func NewOracle(address common.Address, backend bind.ContractBackend) (*Oracle, error) {
	contract, err := bindOracle(address, backend, backend, backend)
	if err != nil {
		return nil, err
	}
	return &Oracle{OracleCaller: OracleCaller{contract: contract}, OracleTransactor: OracleTransactor{contract: contract}, OracleFilterer: OracleFilterer{contract: contract}}, nil
}

// NewOracleCaller creates a new read-only instance of Oracle, bound to a specific deployed contract.
func NewOracleCaller(address common.Address, caller bind.ContractCaller) (*OracleCaller, error) {
	contract, err := bindOracle(address, caller, nil, nil)
	if err != nil {
		return nil, err
	}
	return &OracleCaller{contract: contract}, nil
}

// NewOracleTransactor creates a new write-only instance of Oracle, bound to a specific deployed contract.
func NewOracleTransactor(address common.Address, transactor bind.ContractTransactor) (*OracleTransactor, error) {
	contract, err := bindOracle(address, nil, transactor, nil)
	if err != nil {
		return nil, err
	}
	return &OracleTransactor{contract: contract}, nil
}

// NewOracleFilterer creates a new log filterer instance of Oracle, bound to a specific deployed contract.
func NewOracleFilterer(address common.Address, filterer bind.ContractFilterer) (*OracleFilterer, error) {
	contract, err := bindOracle(address, nil, nil, filterer)
	if err != nil {
		return nil, err
	}
	return &OracleFilterer{contract: contract}, nil
}

// bindOracle binds a generic wrapper to an already deployed contract.
func bindOracle(address common.Address, caller bind.ContractCaller, transactor bind.ContractTransactor, filterer bind.ContractFilterer) (*bind.BoundContract, error) {
	parsed, err := abi.JSON(strings.NewReader(OracleABI))
	if err != nil {
		return nil, err
	}
	return bind.NewBoundContract(address, parsed, caller, transactor, filterer), nil
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_Oracle *OracleRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _Oracle.Contract.OracleCaller.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_Oracle *OracleRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Oracle.Contract.OracleTransactor.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_Oracle *OracleRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _Oracle.Contract.OracleTransactor.contract.Transact(opts, method, params...)
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_Oracle *OracleCallerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _Oracle.Contract.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_Oracle *OracleTransactorRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _Oracle.Contract.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_Oracle *OracleTransactorRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _Oracle.Contract.contract.Transact(opts, method, params...)
}

// GetContractAddress is a free data retrieval call binding the contract method 0x04433bbc.
//
// Solidity: function getContractAddress(string contractName) view returns(address)
func (_Oracle *OracleCaller) GetContractAddress(opts *bind.CallOpts, contractName string) (common.Address, error) {
	var out []interface{}
	err := _Oracle.contract.Call(opts, &out, "getContractAddress", contractName)

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// GetContractAddress is a free data retrieval call binding the contract method 0x04433bbc.
//
// Solidity: function getContractAddress(string contractName) view returns(address)
func (_Oracle *OracleSession) GetContractAddress(contractName string) (common.Address, error) {
	return _Oracle.Contract.GetContractAddress(&_Oracle.CallOpts, contractName)
}

// GetContractAddress is a free data retrieval call binding the contract method 0x04433bbc.
//
// Solidity: function getContractAddress(string contractName) view returns(address)
func (_Oracle *OracleCallerSession) GetContractAddress(contractName string) (common.Address, error) {
	return _Oracle.Contract.GetContractAddress(&_Oracle.CallOpts, contractName)
}

// GetGGPPriceInAVAX is a free data retrieval call binding the contract method 0x78e865fe.
//
// Solidity: function getGGPPriceInAVAX() view returns(uint256 price, uint256 timestamp)
func (_Oracle *OracleCaller) GetGGPPriceInAVAX(opts *bind.CallOpts) (struct {
	Price     *big.Int
	Timestamp *big.Int
}, error) {
	var out []interface{}
	err := _Oracle.contract.Call(opts, &out, "getGGPPriceInAVAX")

	outstruct := new(struct {
		Price     *big.Int
		Timestamp *big.Int
	})
	if err != nil {
		return *outstruct, err
	}

	outstruct.Price = *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)
	outstruct.Timestamp = *abi.ConvertType(out[1], new(*big.Int)).(**big.Int)

	return *outstruct, err

}

// GetGGPPriceInAVAX is a free data retrieval call binding the contract method 0x78e865fe.
//
// Solidity: function getGGPPriceInAVAX() view returns(uint256 price, uint256 timestamp)
func (_Oracle *OracleSession) GetGGPPriceInAVAX() (struct {
	Price     *big.Int
	Timestamp *big.Int
}, error) {
	return _Oracle.Contract.GetGGPPriceInAVAX(&_Oracle.CallOpts)
}

// GetGGPPriceInAVAX is a free data retrieval call binding the contract method 0x78e865fe.
//
// Solidity: function getGGPPriceInAVAX() view returns(uint256 price, uint256 timestamp)
func (_Oracle *OracleCallerSession) GetGGPPriceInAVAX() (struct {
	Price     *big.Int
	Timestamp *big.Int
}, error) {
	return _Oracle.Contract.GetGGPPriceInAVAX(&_Oracle.CallOpts)
}

// GetGGPPriceInAVAXFromOneInch is a free data retrieval call binding the contract method 0x4c97e785.
//
// Solidity: function getGGPPriceInAVAXFromOneInch() view returns(uint256 price, uint256 timestamp)
func (_Oracle *OracleCaller) GetGGPPriceInAVAXFromOneInch(opts *bind.CallOpts) (struct {
	Price     *big.Int
	Timestamp *big.Int
}, error) {
	var out []interface{}
	err := _Oracle.contract.Call(opts, &out, "getGGPPriceInAVAXFromOneInch")

	outstruct := new(struct {
		Price     *big.Int
		Timestamp *big.Int
	})
	if err != nil {
		return *outstruct, err
	}

	outstruct.Price = *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)
	outstruct.Timestamp = *abi.ConvertType(out[1], new(*big.Int)).(**big.Int)

	return *outstruct, err

}

// GetGGPPriceInAVAXFromOneInch is a free data retrieval call binding the contract method 0x4c97e785.
//
// Solidity: function getGGPPriceInAVAXFromOneInch() view returns(uint256 price, uint256 timestamp)
func (_Oracle *OracleSession) GetGGPPriceInAVAXFromOneInch() (struct {
	Price     *big.Int
	Timestamp *big.Int
}, error) {
	return _Oracle.Contract.GetGGPPriceInAVAXFromOneInch(&_Oracle.CallOpts)
}

// GetGGPPriceInAVAXFromOneInch is a free data retrieval call binding the contract method 0x4c97e785.
//
// Solidity: function getGGPPriceInAVAXFromOneInch() view returns(uint256 price, uint256 timestamp)
func (_Oracle *OracleCallerSession) GetGGPPriceInAVAXFromOneInch() (struct {
	Price     *big.Int
	Timestamp *big.Int
}, error) {
	return _Oracle.Contract.GetGGPPriceInAVAXFromOneInch(&_Oracle.CallOpts)
}

// Version is a free data retrieval call binding the contract method 0x54fd4d50.
//
// Solidity: function version() view returns(uint8)
func (_Oracle *OracleCaller) Version(opts *bind.CallOpts) (uint8, error) {
	var out []interface{}
	err := _Oracle.contract.Call(opts, &out, "version")

	if err != nil {
		return *new(uint8), err
	}

	out0 := *abi.ConvertType(out[0], new(uint8)).(*uint8)

	return out0, err

}

// Version is a free data retrieval call binding the contract method 0x54fd4d50.
//
// Solidity: function version() view returns(uint8)
func (_Oracle *OracleSession) Version() (uint8, error) {
	return _Oracle.Contract.Version(&_Oracle.CallOpts)
}

// Version is a free data retrieval call binding the contract method 0x54fd4d50.
//
// Solidity: function version() view returns(uint8)
func (_Oracle *OracleCallerSession) Version() (uint8, error) {
	return _Oracle.Contract.Version(&_Oracle.CallOpts)
}

// SetGGPPriceInAVAX is a paid mutator transaction binding the contract method 0x87da925e.
//
// Solidity: function setGGPPriceInAVAX(uint256 price, uint256 timestamp) returns()
func (_Oracle *OracleTransactor) SetGGPPriceInAVAX(opts *bind.TransactOpts, price *big.Int, timestamp *big.Int) (*types.Transaction, error) {
	return _Oracle.contract.Transact(opts, "setGGPPriceInAVAX", price, timestamp)
}

// SetGGPPriceInAVAX is a paid mutator transaction binding the contract method 0x87da925e.
//
// Solidity: function setGGPPriceInAVAX(uint256 price, uint256 timestamp) returns()
func (_Oracle *OracleSession) SetGGPPriceInAVAX(price *big.Int, timestamp *big.Int) (*types.Transaction, error) {
	return _Oracle.Contract.SetGGPPriceInAVAX(&_Oracle.TransactOpts, price, timestamp)
}

// SetGGPPriceInAVAX is a paid mutator transaction binding the contract method 0x87da925e.
//
// Solidity: function setGGPPriceInAVAX(uint256 price, uint256 timestamp) returns()
func (_Oracle *OracleTransactorSession) SetGGPPriceInAVAX(price *big.Int, timestamp *big.Int) (*types.Transaction, error) {
	return _Oracle.Contract.SetGGPPriceInAVAX(&_Oracle.TransactOpts, price, timestamp)
}

// SetOneInch is a paid mutator transaction binding the contract method 0xa41bfc6a.
//
// Solidity: function setOneInch(address addr) returns()
func (_Oracle *OracleTransactor) SetOneInch(opts *bind.TransactOpts, addr common.Address) (*types.Transaction, error) {
	return _Oracle.contract.Transact(opts, "setOneInch", addr)
}

// SetOneInch is a paid mutator transaction binding the contract method 0xa41bfc6a.
//
// Solidity: function setOneInch(address addr) returns()
func (_Oracle *OracleSession) SetOneInch(addr common.Address) (*types.Transaction, error) {
	return _Oracle.Contract.SetOneInch(&_Oracle.TransactOpts, addr)
}

// SetOneInch is a paid mutator transaction binding the contract method 0xa41bfc6a.
//
// Solidity: function setOneInch(address addr) returns()
func (_Oracle *OracleTransactorSession) SetOneInch(addr common.Address) (*types.Transaction, error) {
	return _Oracle.Contract.SetOneInch(&_Oracle.TransactOpts, addr)
}

// OracleGGPPriceUpdatedIterator is returned from FilterGGPPriceUpdated and is used to iterate over the raw logs and unpacked data for GGPPriceUpdated events raised by the Oracle contract.
type OracleGGPPriceUpdatedIterator struct {
	Event *OracleGGPPriceUpdated // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log          // Log channel receiving the found contract events
	sub  interfaces.Subscription // Subscription for errors, completion and termination
	done bool                    // Whether the subscription completed delivering logs
	fail error                   // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *OracleGGPPriceUpdatedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(OracleGGPPriceUpdated)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(OracleGGPPriceUpdated)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *OracleGGPPriceUpdatedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *OracleGGPPriceUpdatedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// OracleGGPPriceUpdated represents a GGPPriceUpdated event raised by the Oracle contract.
type OracleGGPPriceUpdated struct {
	Price     *big.Int
	Timestamp *big.Int
	Raw       types.Log // Blockchain specific contextual infos
}

// FilterGGPPriceUpdated is a free log retrieval operation binding the contract event 0x1826f74860bd5ff97bcab2245acae00a635acaa3dbc72e5c68b83ff34b1fac00.
//
// Solidity: event GGPPriceUpdated(uint256 indexed price, uint256 timestamp)
func (_Oracle *OracleFilterer) FilterGGPPriceUpdated(opts *bind.FilterOpts, price []*big.Int) (*OracleGGPPriceUpdatedIterator, error) {

	var priceRule []interface{}
	for _, priceItem := range price {
		priceRule = append(priceRule, priceItem)
	}

	logs, sub, err := _Oracle.contract.FilterLogs(opts, "GGPPriceUpdated", priceRule)
	if err != nil {
		return nil, err
	}
	return &OracleGGPPriceUpdatedIterator{contract: _Oracle.contract, event: "GGPPriceUpdated", logs: logs, sub: sub}, nil
}

// WatchGGPPriceUpdated is a free log subscription operation binding the contract event 0x1826f74860bd5ff97bcab2245acae00a635acaa3dbc72e5c68b83ff34b1fac00.
//
// Solidity: event GGPPriceUpdated(uint256 indexed price, uint256 timestamp)
func (_Oracle *OracleFilterer) WatchGGPPriceUpdated(opts *bind.WatchOpts, sink chan<- *OracleGGPPriceUpdated, price []*big.Int) (event.Subscription, error) {

	var priceRule []interface{}
	for _, priceItem := range price {
		priceRule = append(priceRule, priceItem)
	}

	logs, sub, err := _Oracle.contract.WatchLogs(opts, "GGPPriceUpdated", priceRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(OracleGGPPriceUpdated)
				if err := _Oracle.contract.UnpackLog(event, "GGPPriceUpdated", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseGGPPriceUpdated is a log parse operation binding the contract event 0x1826f74860bd5ff97bcab2245acae00a635acaa3dbc72e5c68b83ff34b1fac00.
//
// Solidity: event GGPPriceUpdated(uint256 indexed price, uint256 timestamp)
func (_Oracle *OracleFilterer) ParseGGPPriceUpdated(log types.Log) (*OracleGGPPriceUpdated, error) {
	event := new(OracleGGPPriceUpdated)
	if err := _Oracle.contract.UnpackLog(event, "GGPPriceUpdated", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}
