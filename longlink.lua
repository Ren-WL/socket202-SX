module(...,package.seeall)


require"pins"  --用到了pin库，该库为luatask专用库，需要进行引用
if moduleType == 2 then
    pmd.ldoset(5,pmd.LDO_VMMC)  --使用某些GPIO时，必须在脚本中写代码打开GPIO所属的电压域，配置电压输出输入等级，这些GPIO才能正常工作
end

--设置led的GPIO口
--pins.setup(pio.P0_7,0)

require"socket"
require"pins"
require "utils"
require "pm"
require "common"

-- 配置串口1 -- 蓝牙通信口
pm.wake("mcuUart.lua")
uart.setup(1, 9600, 8, uart.PAR_NONE, uart.STOP_1)
uart.on(1, "receive", function()sys.publish("UART1_RECEIVE") end)
function write(uid, s)
    log.info("testUart.write", s)
    uart.write(uid, s)
end

--帧头类型以及帧尾
--local CMD_SCANNER,CMD_GPIO,CMD_PORT,FRM_TAIL = 1,2,3,string.char(0xC0)


--测试用的服务器信息
local testip,testport = "180.97.81.180", "58931"
--数据发送的消息队列
local msgQuene = {}


local function insertMsg(data)
    table.insert(msgQuene,data)
end
function waitForSend()
    return #msgQuene > 0
end
function outMsgprocess(socketClient)
    --队列中有消息
    while #msgQuene>0 do
        --获取消息，并从队列中删除
        local outMsg = table.remove(msgQuene,1)
        --发送这条消息，并获取发送结果
        local result = socketClient:send(outMsg)
        --发送失败的话立刻返回nil（等同于false）
        if not result then return end
    end
    return true
end
str = string.format("%X",103) 
--local data1 = common.nstrToUcs2Hex("1")

--串口读到的数据缓冲区
local TXhed = {"31","15"} 
local TXend = " B4 15"

function inMsgProcess(socketClient)
    local result,data
    local crc_H = 0xB4
    local crc_L = 0x15

    while true do
        result,data = socketClient:recv(2000)
        --接收到数据
        if result then  --接收成功
            log.info("longlink.inMsgProcess",data)
            --处理data数据
            --SXnum=2&length=103end 
           -- local leng = tonumber((data:sub(1,#data)))
            insertMsg(#data)
            local RX_data_num_T =string.find(data,"num")                            --查询字符串中的num下标
            local RX_data_num_W =string.find(data,"&length")--
            RX_data_num_T= RX_data_num_T+4                                          --下标加4为 数量开始下标
            RX_data_num_W= RX_data_num_W-1                                          --下标减1为 数量结束下标

            local RX_data_length_T =string.find(data,"length")                      --查询字符串中的length头下标
            local RX_data_length_W =string.find(data,"end")                         --查询字符串中的length尾下标
            RX_data_length_T= RX_data_length_T+7                                    --下标加6为 长度开始下标
            RX_data_length_W= RX_data_length_W-1                                    --下标减1为 长度开始下标
           
            insertMsg(RX_data_length_T)
            insertMsg(RX_data_length_W)

            if data:sub(1,2)=="SX"  then 
                local num = tonumber((data:sub(RX_data_num_T,RX_data_num_W)))--拿到num的值 执行循环num次
                local length_MIX = (data:sub(RX_data_length_T,RX_data_length_W))
                local length = tonumber((data:sub(RX_data_length_T,RX_data_length_W))) 
                for i=1,num do
                local array = {"0x1F", "0x0F","0x00","0x04","0x02","0x01",length, crc_H , crc_L }--   ,"0x15"
                   insertMsg(length) 
                   for key,value in ipairs(array) 
                    do
                        --insertMsg(key)
                        --insertMsg(value)
                        write(1, tonumber(value))
                    end
                    
                end
                    num = nil
                    length = nil
                insertMsg("SQ800-end")          
            --[[elseif data == "opendoor" then --打开门操作
                insertMsg("Opened")
                write(1, data) 
                local setGpio1Fnc = pins.setup(pio.P0_7,1) 
            elseif data == "closedoor" then --关闭门操作
                insertMsg("Closed")
                write(1, data) 
                local setGpio1Fnc = pins.setup(pio.P0_7,0)]]
            end
            --如果msgQuene中有等待发送的数据，则立即退出本循环
            if waitForSend() then return true end
        else    --接收失败
            break
        end
    end
    --返回结果，处理成功返回true，处理出错返回false
    return result or data=="timeout"
end
--启动socket客户端任务
sys.taskInit(
function()
    local retryConnectCnt = 0   --失败次数统计
    while true do
        --是否获取到了分配的ip(是否连上网)
        if socket.isReady() then
            --新建一个socket对象，如果是udp只需要把tcp改成udp即可
            local socketClient = socket.tcp()
            --尝试连接指定服务器
            if socketClient:connect(testip,testport) then
                --连接成功
                log.info("longlink.socketClient","connect success")
                retryConnectCnt = 0 --失败次数清零
                --循环处理接收和发送的数据
                while true do
                    if not inMsgProcess(socketClient) then  --接收消息处理函数
                        log.error("longlink.inMsgProcess error")
                        break
                    end
                    if not outMsgprocess(socketClient) then --发送消息处理函数
                        log.error("longlink.outMsgprocess error")
                        break
                    end
                end
            else
                log.info("longlink.socketClient","connect fail")
                --连接失败
                retryConnectCnt = retryConnectCnt+1 --失败次数加一
            end
            socketClient:close()    --断开socket连接
            if retryConnectCnt>=5 then  --失败次数大于五次了
                link.shut()         --强制断开TCP/UDP连接
                retryConnectCnt=0   --失败次数清零
            end
            sys.wait(5000)
        else
            retryConnectCnt = 0     --没连上网，失败次数清零
            --没连上网
            --等待网络环境准备就绪，超时时间是5分钟
            sys.waitUntil("IP_READY_IND",300000)
            --等完了还没连上？
            if not socket.isReady() then
                --进入飞行模式，20秒之后，退出飞行模式
                net.switchFly(true)
                sys.wait(20000)
                net.switchFly(false)
            end
        end
    end
end)
--启动心跳包任务
sys.taskInit(
function()
    while true do
        if socket.isReady() then    --连上网再开始运行
            insertMsg("heart beat") --队列里塞个消息
            sys.wait(10000)         --等待10秒
            

        else    --没连上网别忘了延时！不然会陷入while true死循环，导致模块无法运行其他代码
            sys.wait(1000)          --等待1秒
        end
    end
end)

 
 
 
--[[cec校验
void CrcAdd(unsigned char *cp, unsigned short iLen)
{
 unsigned short InitCrc = 0xffff;
    unsigned short Crc = 0;
 int i = 0;
 int j = 0;

 for(i=0;i<iLen;i++)
 {
  InitCrc ^= cp[i];
  for(j=0;j<8;j++)
  {
   Crc = InitCrc;
   InitCrc >>= 1;
   if(Crc&0x0001)
   {
    InitCrc ^= 0xa001;
   }
  }
 }
 cp[iLen] = InitCrc >> 8;
 cp[iLen + 1] = (unsigned char)InitCrc;
}

unsigned short CrcCalc(const unsigned char *cp, unsigned short len)
{
 unsigned char crcbuf[2];
 unsigned short InitCrc = 0xffff;
    unsigned short Crc = 0;
 int i = 0;
 int j = 0;

 for(i=0;i<len-2;i++)
 {
  InitCrc ^= cp[i];
  for(j=0;j<8;j++)
  {
   Crc = InitCrc;
   InitCrc >>= 1;
   if(Crc&0x0001)
   {
    InitCrc ^= 0xa001;
   }
  }
 }
 crcbuf[0] = InitCrc >> 8;
 crcbuf[1] = (unsigned char)InitCrc;

 if((crcbuf[0]== cp[len-2]) && (crcbuf[1]== cp[len-1]))
 {
  return 0;
 }
 else
 {
  return 1;
 }
}


]]