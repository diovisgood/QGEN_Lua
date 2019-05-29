local tds = require 'tds'

local Account = {}

Account.default_amount = 1

local function numDecimalDigits(n)
  if (n < 0) then n = -n end
  if (n < 0.000000001) then return -9 end
  if (n < 0.00000001) then return -8 end
  if (n < 0.0000001) then return -7 end
  if (n < 0.000001) then return -6 end
  if (n < 0.00001) then return -5 end
  if (n < 0.0001) then return -4 end
  if (n < 0.001) then return -3 end
  if (n < 0.01) then return -2 end
  if (n < 0.1) then return -1 end
  if (n < 1) then return 0 end
  if (n < 10) then return 1 end
  if (n < 100) then return 2 end
  if (n < 1000) then return 3 end
  if (n < 10000) then return 4 end
  if (n < 100000) then return 5 end
  if (n < 1000000) then return 6 end
  if (n < 10000000) then return 7 end
  if (n < 100000000) then return 8 end
  if (n < 1000000000) then return 9 end
  -- 2147483647 is 2^31-1 - add more ifs as needed and adjust this final return as well.
  return 10;
end -- function numDecimalDigits

local function priceToString(self, price)
  if (price == 0) then return '0' end
  if (not self.price_decimals) then
    local n = numDecimalDigits(price)
    self.price_decimals = math.max(0, 3 - n)
  end
  return string.format('%.'..tostring(self.price_decimals)..'f', price)
end -- function priceToString

local function amountToString(self, amount)
  if (amount == math.floor(amount)) then
    return tostring(amount)
  end
  if (not self.amount_decimals) then
    local n = numDecimalDigits(amount)
    self.amount_decimals = math.max(0, 3 - n)
  end
  return string.format('%.'..tostring(self.amount_decimals)..'f', amount)
end -- function amountToString

local function internalToString(self)
  -- Current position and average position price
  local text = 'Position: '..amountToString(self, self.position)
  -- Target position if any
  if self.target_position and (self.position ~= self.target_position) then
    text = text..' Target: '..amountToString(self, self.target_position)
      ..((self.target_position > 0 and ' LONG') or (self.target_position < 0 and ' SHORT') or '')
  else
    text = text..((self.position > 0 and ' LONG') or (self.position < 0 and ' SHORT') or '')
    -- Stop loss and take profit
    if (self.position ~= 0) then
      text = text..' price: '..priceToString(self, self.position_price)
      if self.stop_loss_price then
        text = text..' stop loss: '..priceToString(self, self.stop_loss_price)
      end
      if self.take_profit_price then
        text = text..' take profit: '..priceToString(self, self.take_profit_price)
      end
      if self.trail_stop then
        text = text..' trail stop: '..priceToString(self, self.trail_stop)
      end
      if self.is_trailing then
        text = text..' (trailing'
        if self.trail_stop_price then
          text = text..' best: '..priceToString(self, self.trail_stop_price)
        end
        text = text..')'
      end
    end
  end
  -- Current cash
  if self.cash then
    text = text..'. Cash: '..priceToString(self, self.cash)
  end
  -- Balance
  if self.balance then
    text = text..'. Balance: '..priceToString(self, self.balance)
  end
  return text
end -- function internalToString

local function internalTradeToString(trade)
  local acc = {}
  local text = ''
    ..(trade.operation > 0 and 'LONG ' or 'SHORT ')
    ..amountToString(acc, trade.amount)..' '
    ..priceToString(acc, trade.enter_price)..' -> '..priceToString(acc, trade.exit_price)
    ..(trade.reason and ' '..tostring(trade.reason) or '')
    ..' Result: '..priceToString(acc, trade.result or 0)
    ..' Commission: '..priceToString(acc, trade.commission or 0)
  return text
end -- function internalTradeToString


function Account.init(self)
  self = self or {}
  -- Check properties
  self.position = self.position or 0
  self.trades = self.trades or tds.Vec()
  self.initial_balance = self.initial_balance or 100000
  self.cash = self.cash or self.initial_balance
  self.balance = self.balance or self.cash
  self.slippage = self.slippage or nil
  -- Update metatable.__index
  return setmetatable(self, { __index = Account, __tostring = internalToString })
end -- function Account.init

function Account:buyLongStopLossTakeProfit(amount, stop_loss_price, take_profit_price, trail_stop)
  self.target_position = amount
  self.stop_loss_price = stop_loss_price
  self.take_profit_price = take_profit_price
  self.trail_stop = (trail_stop or 0)
  self.is_trailing = nil
  self.trail_stop_price = nil
end -- function Account:buyLongStopLossTakeProfit

function Account:sellShortStopLossTakeProfit(amount, stop_loss_price, take_profit_price, trail_stop)
  self.target_position = -amount
  self.stop_loss_price = stop_loss_price
  self.take_profit_price = take_profit_price
  self.trail_stop = (trail_stop or 0)
  self.is_trailing = nil
  self.trail_stop_price = nil
end -- function Account:sellShortStopLossTakeProfit

function Account:processTick(price, datetime)
  if (not self.target_position) then
    -- Update balance
    self.balance = self.cash + self.position*price
    return
  end
  -- Enter position if needed
  if (self.position ~= self.target_position) then
    -- Perform trade to setup new position
    self:trade((self.target_position - self.position), price, datetime)
    -- Callback
    if (type(self.onPosition) == 'function') then
      self.onPosition(self)
    end
  elseif (self.position == self.target_position) then
    local direction = (self.position > 0 and 1) or (self.position < 0 and -1) or 0
    -- Check for reaching stop loss price
    if self.stop_loss_price and (direction*(price - self.stop_loss_price) <= 0) then
      self:closePosition(price, datetime, 'StopLoss')
      -- Callback
      if (type(self.onStopLoss) == 'function') then
        self.onStopLoss(self, self.trades[#self.trades])
      end
    end
    -- Check for reaching take profit price
    if (not self.is_trailing) and self.take_profit_price
    and (direction*(price - self.take_profit_price) >= 0) then
      self.is_trailing = true
      self.trail_stop_price = price
    end
    -- Check for reaching trail stop
    if self.is_trailing then
      if (direction*(price - self.trail_stop_price) > 0) then
        -- Update trail stop price
        self.trail_stop_price = price
      elseif (direction*(self.trail_stop_price - price) >= self.trail_stop) then
        -- Close position
        self:closePosition(price, datetime, 'TrailStop')
        -- Callback
        if (type(self.onTrailStop) == 'function') then
          self.onTrailStop(self, self.trades[#self.trades])
        end
      end
    end -- if is_trailing
  end -- if target_position
  -- Update balance
  self.balance = self.cash + self.position*price
end -- function Account:processTick

function Account.emulateCandle(TO, TC, O, H, L, C, callback)
  local N = 10
  local P = (math.random() >= 0.5) and { O, H, L, C } or { O, L, H, C }
  
  callback(O, TO)
  
  for i = 2, #P do
    local p1, p2 = P[i-1], P[i]
    if (p1 == p2) then
      callback(p2, TO + ((i-2)*N+N)*(TC - TO)/(3*N))
    else
      for j = 1, N do
        local p = p1 + j*(p2 - p1)/N
        local t = TO + ((i-2)*N+j)*(TC - TO)/(3*N)
        callback(p, t)
      end
    end
  end
end -- function Account.emulateCandle

function Account:processCandle(TO, TC, O, H, L, C)
  Account.emulateCandle(TO, TC, O, H, L, C,
    function(price, datetime)
      self:processTick(price, datetime)
    end)
end -- function Account:processCandle

function Account:longPosition(price, datetime)
  assert(price > 0, 'Account:longPosition: Invalid price')
  assert(datetime, 'Account:longPosition: Invalid datetime')
  -- Apply price slippage if needed
  if self.slippage then
    price = price*(1 + self.slippage)
  end
  -- Update position
  if (self.position > 0) then
    return
  elseif (self.position < 0) then
    self:closePosition(price, datetime)
  end
  self.position = (Account.default_amount or 1)
  self.position_datetime = datetime
  self.position_price = price
  -- Update cash
  self.cash = self.cash - self.position*price
  -- Update balance
  self.balance = self.cash + self.position*price
  -- Save last trade price and datetime
  self.last_trade_price = price
  self.last_trade_time = datetime
end -- function Account:longPosition

function Account:shortPosition(price, datetime)
  assert(price > 0, 'Account:shortPosition: Invalid price')
  assert(datetime, 'Account:shortPosition: Invalid datetime')
  -- Apply price slippage if needed
  if self.slippage then
    price = price*(1 - self.slippage)
  end
  -- Update position
  if (self.position < 0) then
    return
  elseif (self.position > 0) then
    self:closePosition(price, datetime)
  end
  self.position = -(Account.default_amount or 1)
  self.position_datetime = datetime
  self.position_price = price
  -- Update cash
  self.cash = self.cash - self.position*price
  -- Update balance
  self.balance = self.cash + self.position*price
  -- Save last trade price and datetime
  self.last_trade_price = price
  self.last_trade_time = datetime
end -- function Account:shortPosition

local function getComission(self, trade)
  local ct = type(self.commission)
  if (ct == 'function') then
    return self.commission(trade)
  elseif (ct == 'number') then
    return self.commission
  end
  return 0
end -- function getComission

function Account:resetStopLoss()
  self.stop_loss_price = nil
end -- function Account:resetStopLoss

function Account:resetTakeProfit()
  self.take_profit_price = nil
  self.trail_stop = nil
  self.is_trailing = nil
  self.trail_stop_price = nil
end -- function Account:resetTakeProfit

function Account:resetStop()
  self:resetStopLoss()
  self:resetTakeProfit()
end -- function Account:resetStop

local function internalAddTrade(self, trade)
  self.trades:insert(tds.Hash(trade))
  -- Callback
  if (type(self.onTrade) == 'function') then
    self.onTrade(self, setmetatable(trade, { __tostring = internalTradeToString }))
  end
end -- function internalAddTrade

local function internalClosePosition(self, price, datetime, reason)
  if (self.position ~= 0) then
    local trade = {
      operation = (self.position > 0) and 1 or -1,
      amount = math.abs(self.position),
      enter_date = self.position_datetime,
      enter_price = self.position_price,
      exit_date = datetime,
      exit_price = price,
      result = self.position*(price - self.position_price),
      reason = reason,
    }
    trade.commission = getComission(self, trade)
    -- Update cash
    self.cash = self.cash + self.position*price - trade.commission
    -- Clear position
    self.position = 0
    -- Update balance
    self.balance = self.cash
    -- Save last trade price and datetime
    self.last_trade_price = price
    self.last_trade_time = datetime
    -- Add trade to the list of trades
    internalAddTrade(self, trade)
  end
end -- function internalClosePosition

function Account:closePosition(price, datetime, reason)
  if (self.position ~= 0) then
    -- Clear stop loss and take profit settings
    self:resetStop()
    -- Clear target position
    self.target_position = nil
    -- Close position
    internalClosePosition(self, price, datetime, reason)
  end
end -- function Account:closePosition

function Account:trade(amount, price, datetime)
  assert(amount ~= 0, 'Account:trade: Invalid amount')
  assert(price > 0, 'Account:trade: Invalid price')
  assert(datetime, 'Account:trade: Invalid datetime')

  -- Apply price slippage if needed
  if self.slippage then
    price = price*(1 + (amount > 0 and 1 or -1)*self.slippage)
  end

  -- If no previous position - simply update
  if (self.position == 0) then
    self.position = amount
    self.position_datetime = datetime
    self.position_price = price
    -- Update cash
    self.cash = self.cash - amount*price
    -- Update balance
    self.balance = self.cash + self.position*price
    -- Save last trade price and datetime
    self.last_trade_price = price
    self.last_trade_time = datetime
    return
  end
  
  local new_position = (self.position + amount)
  
  -- Check if we are increasing or closing current position
  if (self.position*amount > 0) then
    -- Position is increased by amount
    self.position_price = (self.position*self.position_price + amount*price) / new_position
    self.position = new_position
    -- Update cash
    self.cash = self.cash - amount*price
    -- Update balance
    self.balance = self.cash + self.position*price
  else
    if (self.position*new_position > 0) then
      -- Position is decreased by amount
      -- Create new trade
      local trade = {
        operation = (self.position > 0) and 1 or -1,
        amount = math.abs(amount),
        enter_date = self.position_datetime,
        enter_price = self.position_price,
        exit_date = datetime,
        exit_price = price,
        result = (self.position > 0 and 1 or -1)*math.abs(amount)*(price - self.position_price),
      }
      trade.commission = getComission(self, trade)
      -- Update cash
      self.cash = self.cash + amount*price - trade.commission
      -- Update position
      self.position = new_position
      -- Update balance
      self.balance = self.cash + self.position*price
      -- Add trade to the list of trades
      internalAddTrade(self, trade)
    else
      -- Position is reversed
      -- Close position
      internalClosePosition(self, price, datetime)
      -- Setup new position
      self.position = new_position
      self.position_datetime = datetime
      self.position_price = price
      -- Update cash
      self.cash = self.cash - self.position*price
      -- Update balance
      self.balance = self.cash + self.position*price
    end
  end
  -- Save last trade price and datetime
  self.last_trade_price = price
  self.last_trade_time = datetime
end -- function Account:trade

function Account.makeReportFromTrades(trades, initial_balance, first_time, last_time)
  initial_balance = initial_balance or 100000
  local net_profit = 0
  local gross_profit = 0
  local gross_loss = 0
  local total_comission = 0
  
  local max_net_profit = 0
  local max_drawdown = 0
  local max_drawdown_percent = 0
  
  local n_trades = #trades
  local n_trades_win = 0
  local n_trades_loss = 0
  local trades_length = 0
  local trades_length_win = 0
  local trades_length_loss = 0
  
  for _,trade in ipairs(trades) do
    if (not first_time) or (first_time > trade.enter_date) then first_time = trade.enter_date end
    if (not last_time) or (last_time < trade.exit_date) then last_time = trade.exit_date end
    local result = (trade.result or 0) - (trade.commission or 0)
    local length = (trade.exit_date - trade.enter_date)
    -- Calculate some integral features
    net_profit = (net_profit or 0) + result
    gross_profit = gross_profit + (result>0 and result or 0)
    gross_loss = gross_loss + (result<0 and (-result) or 0)
    total_comission = total_comission + (trade.commission or 0)
    n_trades_win = n_trades_win + (result>0 and 1 or 0)
    n_trades_loss = n_trades_loss + (result<0 and 1 or 0)
    trades_length = trades_length + length
    trades_length_win = trades_length_win + (result>0 and length or 0)
    trades_length_loss = trades_length_loss + (result<0 and length or 0)
    -- Calculate max drawdown
    if (max_net_profit < net_profit) then max_net_profit = net_profit end
    if (max_drawdown < (max_net_profit-net_profit)) then
      max_drawdown = (max_net_profit-net_profit)
      max_drawdown_percent = max_drawdown/(initial_balance+max_net_profit)
    end
  end -- for trades
  
  local annual_rate
  if first_time and last_time then
    local seconds = last_time - first_time
    annual_rate = (seconds > 0) and (net_profit/initial_balance)*365*24*60*60/seconds
    if annual_rate ~= annual_rate then annual_rate = nil end
  end
  
  local report = {
    net_profit = net_profit,
    profit_factor = (gross_loss>0 and (gross_profit/gross_loss)),
    rate_of_return = (net_profit/initial_balance),
    annual_rate = annual_rate,
    max_drawdown = max_drawdown,
    max_drawdown_percent = max_drawdown_percent,
    recovery_factor = (annual_rate and max_drawdown_percent) and (annual_rate/(max_drawdown_percent+1e-5)),
    gross_profit = gross_profit,
    gross_loss = gross_loss,
    total_comission = total_comission,
    n_trades = n_trades,
    n_trades_win = n_trades_win,
    n_trades_loss = n_trades_loss,
    average_trade = (n_trades>0 and (net_profit/n_trades)),
    average_trade_win = (n_trades_win>0 and (gross_profit/n_trades_win)),
    average_trade_loss = (n_trades_loss>0 and (gross_loss/n_trades_loss)),
    average_trade_length = (n_trades>0 and (trades_length/n_trades)),
    average_trade_length_win = (n_trades_win>0 and (trades_length_win/n_trades_win)),
    average_trade_length_loss = (n_trades_loss>0 and (trades_length_loss/n_trades_loss)),
  }
  
  return report
end -- function Account.makeReportFromTrades

function Account:makeReport(first_time, last_time)
  return Account.makeReportFromTrades(self.trades, self.initial_balance, first_time, last_time)
end -- function Account:makeReport

-- Check if running from console
local info = debug.getinfo(2)
if info and (info.name or (info.what ~= 'C')) then
  return Account
end

math.randomseed(os.time())

Account.emulateCandle(0, 10, 100, 120, 80, 85, function(p, t) print(p, t) end)

Account.emulateCandle(0, 10, 100, 100, 80, 85, function(p, t) print(p, t) end)
