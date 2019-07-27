PROJECT = "SOCKET-TEST"
VERSION = "1.0.0"


require "log"
LOG_LEVEL = log.LOGLEVEL_TRACE
require "sys"
--每1分钟查询一次GSM信号强度,每1分钟查询一次基站信息
require "net"
net.startQueryAll(60000, 60000)
--加载硬件看门狗功能模块
require "wdt"
wdt.setup(pio.P0_30, pio.P0_31)
--加载网络指示灯功能模块
require "netLed"
netLed.setup(true,moduleType == 2 and pio.P1_1 or pio.P2_0,moduleType == 2 and nil or pio.P2_1)
require"longlink"
require"ntp"

require "errDump"
errDump.request("udp://ota.airm2m.com:9072")
--require "ledtest"    --led
ntp.timeSync()
--启动系统框架
sys.init(0, 0)
sys.run()




