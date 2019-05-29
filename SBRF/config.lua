
History_File_Prefix = 'SPFB.SBRF'

Sec_Name = 'SPBFUT.SRU8'

Dataset_File = 'dataset.gz'

Frame_Interval = 600

Species_Count_Limit = 70

Population_Size = 100

Iterations_In_Epoch = 20

Autosave_Interval = 2

Positive_Rate_Epochs_Limit = 50

Positive_Rate_Update_Limit = 4

Negative_Rate_Epochs_Limit = 20
Negative_Rate_Profit_Factor_Limit = 1.5

local Robot = {
  id = Sec_Name,
  class_code = Sec_Name:match('^(%a+)%.'),
  sec_code = Sec_Name:match('%.([%a%d]+)$'),
  source = 'candles',
  interval = 60,
  host = '192.168.56.101',
  port = 3789,
  emulate = false,
  trading_amount = 16,
}

return Robot
