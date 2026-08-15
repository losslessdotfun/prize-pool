pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VariableTaxERC20 is ERC20 {

    struct EpochSchedule {
        uint256 duration;
        uint256 taxRateBPS;
    }

    EpochSchedule[] public schedule;

    uint256 public immutable _start;
    uint256 public _cycleDuration;
    
    uint256 public _rebates;
    address public _controller;

    mapping(address => bool) public _exempt;

    event TaxExemptionAdded(address subsidiary);
    event TaxRebate(address benefactor, uint256 amount);
    event ScheduleUpdated(uint256 totalDuration, uint256 numberOfEpochs);

    constructor(
        string memory name,
        string memory symbol,
        address controller,
        uint256 supply,
        uint256[] memory initialDurations,
        uint256[] memory initialRates
    )
        ERC20(name, symbol)
    {
        require(initialDurations.length > 0, "Schedule must not be empty");
        require(initialDurations.length == initialRates.length, "Durations and rates must match");

        _controller = controller;
        _start = block.timestamp;

        _exempt[controller] = true;
        _exempt[address(0)] = true;

        _updateSchedule(initialDurations, initialRates);

        _mint(msg.sender, supply);
    }

    modifier onlyController() {
        require(msg.sender == _controller, "Invalid controller");
        _;
    }

     function currentEpochIndex() public view returns (uint256) {
        if (_cycleDuration == 0) return 0;

        uint256 elapsedTime = block.timestamp - _start;
        uint256 timeInCycle = elapsedTime % _cycleDuration;
        uint256 accumulatedTime = 0;

        for (uint256 i = 0; i < schedule.length; i++) {
            accumulatedTime += schedule[i].duration;

            if (timeInCycle < accumulatedTime) return i;
        }

        returon 0; 
    }

    function tax(address from, address to, uint256 amount) public view returns (uint256) {
        bool taxable = !_exempt[to] && !_exempt[from];

        if (!taxable) return 0;

        uint256 epochIndex = currentEpochIndex();
        uint256 currentTaxRate = schedule[epochIndex].taxRateBPS;

        return (amount * currentTaxRate) / 10000;
    }
 
    function _deductTax(address from, uint256 amount) internal {
        _rebates += amount;
        super._burn(from, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint256 taxAmount = tax(msg.sender, to, amount);

        if (taxAmount > 0) _deductTax(msg.sender, taxAmount);

        super._transfer(msg.sender, to, amount - taxAmount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        uint256 taxAmount = tax(from, to, amount);
 
        super._spendAllowance(from, _msgSender(), amount);

        super._transfer(from, to, amount - taxAmount);

        if (taxAmount > 0) _deductTax(from, taxAmount);

        return true;
    }

    function updateSchedule(
        uint256[] memory durations, 
        uint256[] memory rates
    ) external onlyController {
        _updateSchedule(durations, rates);
    }

    function setTaxExemption(address account) external onlyController {
        _exempt[account] = true;
        emit TaxExemptionAdded(account);
    }

    function rebate(address to, uint256 amount) public onlyController {
        require(to != address(0), "Cannot rebate to zero address");
        require(amount > 0, "Rebate amount must be greater than zero");
        require(_rebates >= amount, "Insufficient taxes collected");

        _rebates -= amount;
        _mint(to, amount);

        emit TaxRebate(to, amount);
    }

    function _updateSchedule(uint256[] memory durations, uint256[] memory rates) internal {
        require(durations.length > 0, "Schedule must not be empty");
        require(durations.length == rates.length, "Durations and rates must match");

        delete schedule; 
        _cycleDuration = 0; 

        for (uint256 i = 0; i < durations.length; i++) {
            require(rates[i] <= 10000, "Tax rate must be <= 10000 BPS (100%)");

            schedule.push(EpochSchedule({
                duration: durations[i],
                taxRateBPS: rates[i]
            }));

            _cycleDuration += durations[i];
        }

        emit ScheduleUpdated(_cycleDuration, schedule.length);
    }

}
