//+------------------------------------------------------------------+
//|                                                 TUTTO_VISUAL_CORE.mq5 |
//|                                    TUTTO Market Geometry Engine   |
//|                        Market Structure Visualization Indicator   |
//+------------------------------------------------------------------+
#property copyright "TUTTO Project"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   5

//--- Plot 1: STATE4 Arrow (Blue)
#property indicator_label1  "STATE4"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: STATE5 Arrow (Green)
#property indicator_label2  "STATE5"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- Plot 3: Entry Line
#property indicator_label3  "Entry"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrWhite
#property indicator_style3  STYLE_SOLID
#property indicator_width3  3

//--- Plot 4: TP Lines
#property indicator_label4  "TP"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGold
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

//--- Plot 5: SL Line
#property indicator_label5  "SL"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

//--- Input Parameters
input int      InpLookback = 500;           // Lookback period
input bool     InpShowPanel = true;         // Show info panel
input color    InpPanelBgColor = clrBlack;  // Panel background color
input color    InpPanelTextColor = clrWhite;// Panel text color
input int      InpPanelFontSize = 9;        // Panel font size
input int      InpPanelX = 20;              // Panel X position
input int      InpPanelY = 20;              // Panel Y position
input bool     InpUseMTF = false;           // Enable MTF (Multi-Timeframe)
input ENUM_TIMEFRAMES InpMTF1 = PERIOD_M1;  // MTF Timeframe 1
input ENUM_TIMEFRAMES InpMTF2 = PERIOD_M5;  // MTF Timeframe 2
input ENUM_TIMEFRAMES InpMTF3 = PERIOD_M15; // MTF Timeframe 3
input ENUM_TIMEFRAMES InpMTF4 = PERIOD_H1;  // MTF Timeframe 4
input ENUM_TIMEFRAMES InpMTF5 = PERIOD_H4;  // MTF Timeframe 5
input ENUM_TIMEFRAMES InpMTF6 = PERIOD_D1;  // MTF Timeframe 6
input ENUM_TIMEFRAMES InpMTF7 = PERIOD_W1;  // MTF Timeframe 7

//--- Fibonacci Levels
double FIB_0 = 0.0;
double FIB_0_5 = 0.5;
double FIB_0_618 = 0.618;
double FIB_1 = 1.0;
double FIB_2_33 = 2.33;
double FIB_2_618 = 2.618;
double FIB_3_236 = 3.236;
double FIB_3_77 = 3.77;
double FIB_4_236 = 4.236;
double FIB_6_854 = 6.854;

//--- Indicator Buffers
double BufferSTATE4[];
double BufferSTATE5[];
double BufferEntry[];
double BufferTP[];
double BufferSL[];

//--- Global Variables
int handleEMA200;
double ema200Buffer[];
double highBuffer[];
double lowBuffer[];
double closeBuffer[];

//--- MTF Variables
int handleMTF_EMA200[7];
double mtfEma200Buffer[7][];
ENUM_TIMEFRAMES mtfTimeframes[7];

//--- Structure Tracking
struct WaveStructure
{
    int      state;
    double   fib0;
    double   fib1;
    double   fib2_33;
    double   fib2_618;
    double   fib4_236;
    double   entry;
    double   tp1;
    double   tp2;
    double   tp3;
    double   sl;
    int      direction;  // 1 = up, -1 = down
    int      fib0Bar;
    int      fib1Bar;
    bool     state4Confirmed;
    bool     state5Confirmed;
    bool     state6Reached;
    bool     state7Reached;
    bool     state8Reached;
};

WaveStructure currentWave;
WaveStructure prevWave;

//--- Panel Objects
string panelPrefix = "TUTTO_PANEL_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Set indicator buffers
    SetIndexBuffer(0, BufferSTATE4, INDICATOR_DATA);
    SetIndexBuffer(1, BufferSTATE5, INDICATOR_DATA);
    SetIndexBuffer(2, BufferEntry, INDICATOR_DATA);
    SetIndexBuffer(3, BufferTP, INDICATOR_DATA);
    SetIndexBuffer(4, BufferSL, INDICATOR_DATA);
    
    //--- Set empty values
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    
    //--- Set arrow codes
    PlotIndexSetInteger(0, PLOT_ARROW, 233);  // Blue arrow up
    PlotIndexSetInteger(1, PLOT_ARROW, 234);  // Green arrow up
    
    //--- Initialize EMA200 handle
    handleEMA200 = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
    if(handleEMA200 == INVALID_HANDLE)
    {
        Print("Error creating EMA200 handle: ", GetLastError());
        return(INIT_FAILED);
    }
    
    //--- Initialize MTF EMA200 handles if enabled
    if(InpUseMTF)
    {
        mtfTimeframes[0] = InpMTF1;
        mtfTimeframes[1] = InpMTF2;
        mtfTimeframes[2] = InpMTF3;
        mtfTimeframes[3] = InpMTF4;
        mtfTimeframes[4] = InpMTF5;
        mtfTimeframes[5] = InpMTF6;
        mtfTimeframes[6] = InpMTF7;
        
        for(int i = 0; i < 7; i++)
        {
            handleMTF_EMA200[i] = iMA(_Symbol, mtfTimeframes[i], 200, 0, MODE_EMA, PRICE_CLOSE);
            if(handleMTF_EMA200[i] == INVALID_HANDLE)
            {
                Print("Error creating MTF EMA200 handle for timeframe ", i, ": ", GetLastError());
                // Continue with other timeframes
            }
            ArraySetAsSeries(mtfEma200Buffer[i], true);
        }
    }
    
    //--- Initialize arrays
    ArraySetAsSeries(ema200Buffer, true);
    ArraySetAsSeries(highBuffer, true);
    ArraySetAsSeries(lowBuffer, true);
    ArraySetAsSeries(closeBuffer, true);
    ArraySetAsSeries(BufferSTATE4, true);
    ArraySetAsSeries(BufferSTATE5, true);
    ArraySetAsSeries(BufferEntry, true);
    ArraySetAsSeries(BufferTP, true);
    ArraySetAsSeries(BufferSL, true);
    
    //--- Initialize wave structure
    ResetWaveStructure(currentWave);
    ResetWaveStructure(prevWave);
    
    //--- Create panel objects
    if(InpShowPanel)
        CreatePanel();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handle
    if(handleEMA200 != INVALID_HANDLE)
        IndicatorRelease(handleEMA200);
    
    //--- Release MTF handles
    if(InpUseMTF)
    {
        for(int i = 0; i < 7; i++)
        {
            if(handleMTF_EMA200[i] != INVALID_HANDLE)
                IndicatorRelease(handleMTF_EMA200[i]);
        }
    }
    
    //--- Delete panel objects
    DeletePanel();
    
    //--- Delete all marker objects
    ObjectsDeleteAll(0, "TUTTO_STATE");
}

//+------------------------------------------------------------------+
//| Reset wave structure                                              |
//+------------------------------------------------------------------+
void ResetWaveStructure(WaveStructure &wave)
{
    wave.state = 0;
    wave.fib0 = 0;
    wave.fib1 = 0;
    wave.fib2_33 = 0;
    wave.fib2_618 = 0;
    wave.fib4_236 = 0;
    wave.entry = 0;
    wave.tp1 = 0;
    wave.tp2 = 0;
    wave.tp3 = 0;
    wave.sl = 0;
    wave.direction = 0;
    wave.fib0Bar = -1;
    wave.fib1Bar = -1;
    wave.state4Confirmed = false;
    wave.state5Confirmed = false;
    wave.state6Reached = false;
    wave.state7Reached = false;
    wave.state8Reached = false;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    //--- Check for minimum bars
    if(rates_total < 300)
        return(0);
    
    //--- Set arrays as series
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    //--- Copy EMA200 data
    if(CopyBuffer(handleEMA200, 0, 0, rates_total, ema200Buffer) <= 0)
        return(0);
    ArraySetAsSeries(ema200Buffer, true);
    
    //--- Copy MTF EMA200 data if enabled
    if(InpUseMTF)
    {
        for(int i = 0; i < 7; i++)
        {
            if(handleMTF_EMA200[i] != INVALID_HANDLE)
            {
                if(CopyBuffer(handleMTF_EMA200[i], 0, 0, rates_total, mtfEma200Buffer[i]) <= 0)
                {
                    // If copy fails, continue with other timeframes
                    continue;
                }
                ArraySetAsSeries(mtfEma200Buffer[i], true);
            }
        }
    }
    
    //--- Calculate start position
    int start;
    if(prev_calculated == 0)
    {
        //--- First calculation - initialize all buffers
        start = rates_total - 1;
        for(int i = 0; i < rates_total; i++)
        {
            BufferSTATE4[i] = EMPTY_VALUE;
            BufferSTATE5[i] = EMPTY_VALUE;
            BufferEntry[i] = EMPTY_VALUE;
            BufferTP[i] = EMPTY_VALUE;
            BufferSL[i] = EMPTY_VALUE;
        }
        
        //--- Reset wave structure for fresh start
        ResetWaveStructure(currentWave);
        ResetWaveStructure(prevWave);
        
        //--- Delete all old marker objects
        ObjectsDeleteAll(0, "TUTTO_STATE");
    }
    else
    {
        //--- Only process new bars (prev_calculated to rates_total-1)
        start = prev_calculated - 1;
    }
    
    //--- Limit lookback for initial calculation
    int lookback = MathMin(InpLookback, rates_total - 1);
    
    //--- Process bars
    //--- For first calculation, process all bars in lookback
    //--- For subsequent calculations, only process new bars
    if(prev_calculated == 0)
    {
        //--- Process from oldest to newest (confirmed bars only)
        for(int i = lookback; i >= 1; i--)
        {
            ProcessBar(i, high, low, close, time);
        }
    }
    else
    {
        //--- Only process the newly confirmed bar (bar 1)
        if(rates_total > 1)
        {
            ProcessBar(1, high, low, close, time);
        }
    }
    
    //--- Update panel
    if(InpShowPanel)
        UpdatePanel(close[0], ema200Buffer[0]);
    
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Process individual bar                                            |
//+------------------------------------------------------------------+
void ProcessBar(const int bar,
                const double &high[],
                const double &low[],
                const double &close[],
                const datetime &time[])
{
    double barHigh = high[bar];
    double barLow = low[bar];
    double barClose = close[bar];
    
    //--- STATE1: Wave Origin Candidate (Fractal detection)
    if(currentWave.state == 0)
    {
        if(IsFractal(bar, high, low))
        {
            currentWave.fib0 = IsTopFractal(bar, high, low) ? barHigh : barLow;
            currentWave.fib0Bar = bar;
            currentWave.direction = IsTopFractal(bar, high, low) ? -1 : 1;
            currentWave.state = 1;
        }
    }
    //--- STATE2: Fib1 Confirmed
    else if(currentWave.state == 1)
    {
        double fib1Target = CalculateFibLevel(currentWave.fib0, currentWave.direction, FIB_1);
        
        if(currentWave.direction == 1 && barHigh >= fib1Target)
        {
            currentWave.fib1 = barHigh;
            currentWave.fib1Bar = bar;
            currentWave.state = 2;
        }
        else if(currentWave.direction == -1 && barLow <= fib1Target)
        {
            currentWave.fib1 = barLow;
            currentWave.fib1Bar = bar;
            currentWave.state = 2;
        }
    }
    //--- STATE3: Pullback Candidate
    else if(currentWave.state == 2)
    {
        //--- Wait for pullback structure
        if(HasPullbackStructure(bar, high, low, close))
        {
            currentWave.state = 3;
        }
    }
    //--- STATE4: Market Geometry Acceptance
    else if(currentWave.state == 3)
    {
        if(HasMiniFibStructure(bar, high, low, close))
        {
            currentWave.state = 4;
            currentWave.state4Confirmed = true;
            
            //--- Calculate entry, TP, SL
            CalculateTradeLevels(currentWave);
            
            //--- Draw STATE4 arrow (Blue)
            BufferSTATE4[bar] = currentWave.direction == 1 ? barLow : barHigh;
            
            //--- Draw entry line
            for(int j = 0; j < 100 && (bar + j) < ArraySize(BufferEntry); j++)
            {
                BufferEntry[bar + j] = currentWave.entry;
            }
            
            //--- Draw TP lines
            for(int j = 0; j < 100 && (bar + j) < ArraySize(BufferTP); j++)
            {
                BufferTP[bar + j] = currentWave.tp1;
            }
            
            //--- Draw SL line
            for(int j = 0; j < 100 && (bar + j) < ArraySize(BufferSL); j++)
            {
                BufferSL[bar + j] = currentWave.sl;
            }
        }
    }
    //--- STATE5: Pullback Authentication (occurs with STATE4)
    else if(currentWave.state == 4 && !currentWave.state5Confirmed)
    {
        if(ConfirmFib1Formation(bar, high, low, close))
        {
            currentWave.state = 5;
            currentWave.state5Confirmed = true;
            
            //--- Draw STATE5 arrow (Green)
            BufferSTATE5[bar] = currentWave.direction == 1 ? barLow : barHigh;
        }
    }
    //--- STATE6: Fib2.33 Reached
    else if(currentWave.state >= 5 && !currentWave.state6Reached)
    {
        double fib2_33Target = CalculateFibLevel(currentWave.fib0, currentWave.direction, FIB_2_33);
        
        if((currentWave.direction == 1 && barHigh >= fib2_33Target) ||
           (currentWave.direction == -1 && barLow <= fib2_33Target))
        {
            currentWave.fib2_33 = currentWave.direction == 1 ? barHigh : barLow;
            currentWave.state6Reached = true;
            currentWave.state = 6;
            
            //--- Draw cyan marker
            string markerName = "TUTTO_STATE6_" + IntegerToString(bar);
            DrawMarker(markerName, time[bar], currentWave.fib2_33, clrCyan, 159);
        }
    }
    //--- STATE7: Fib2.618 Reached
    else if(currentWave.state >= 6 && !currentWave.state7Reached)
    {
        double fib2_618Target = CalculateFibLevel(currentWave.fib0, currentWave.direction, FIB_2_618);
        
        if((currentWave.direction == 1 && barHigh >= fib2_618Target) ||
           (currentWave.direction == -1 && barLow <= fib2_618Target))
        {
            currentWave.fib2_618 = currentWave.direction == 1 ? barHigh : barLow;
            currentWave.state7Reached = true;
            currentWave.state = 7;
            
            //--- Draw yellow marker
            string markerName = "TUTTO_STATE7_" + IntegerToString(bar);
            DrawMarker(markerName, time[bar], currentWave.fib2_618, clrYellow, 159);
        }
    }
    //--- STATE8: Fib4.236 Reached
    else if(currentWave.state >= 7 && !currentWave.state8Reached)
    {
        double fib4_236Target = CalculateFibLevel(currentWave.fib0, currentWave.direction, FIB_4_236);
        
        if((currentWave.direction == 1 && barHigh >= fib4_236Target) ||
           (currentWave.direction == -1 && barLow <= fib4_236Target))
        {
            currentWave.fib4_236 = currentWave.direction == 1 ? barHigh : barLow;
            currentWave.state8Reached = true;
            currentWave.state = 8;
            
            //--- Draw red marker
            string markerName = "TUTTO_STATE8_" + IntegerToString(bar);
            DrawMarker(markerName, time[bar], currentWave.fib4_236, clrRed, 159);
            
            //--- Reset for new wave
            prevWave = currentWave;
            ResetWaveStructure(currentWave);
        }
    }
    
    //--- Reset if structure fails
    if(currentWave.state > 0 && currentWave.state < 4)
    {
        if(StructureFailed(bar, high, low, close))
        {
            prevWave = currentWave;
            ResetWaveStructure(currentWave);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci level                                          |
//+------------------------------------------------------------------+
double CalculateFibLevel(double basePrice, int direction, double fibLevel)
{
    double range = 0;
    
    if(currentWave.fib1 != 0 && currentWave.fib0 != 0)
    {
        range = MathAbs(currentWave.fib1 - currentWave.fib0);
    }
    
    if(direction == 1)  // Upward
        return currentWave.fib0 + (range * fibLevel);
    else  // Downward
        return currentWave.fib0 - (range * fibLevel);
}

//+------------------------------------------------------------------+
//| Check if bar is a fractal                                        |
//+------------------------------------------------------------------+
bool IsFractal(const int bar, const double &high[], const double &low[])
{
    if(bar < 2 || bar >= ArraySize(high) - 2)
        return false;
    
    //--- Top fractal
    if(high[bar] > high[bar+1] && high[bar] > high[bar+2] &&
       high[bar] > high[bar-1] && high[bar] > high[bar-2])
        return true;
    
    //--- Bottom fractal
    if(low[bar] < low[bar+1] && low[bar] < low[bar+2] &&
       low[bar] < low[bar-1] && low[bar] < low[bar-2])
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if fractal is top fractal                                  |
//+------------------------------------------------------------------+
bool IsTopFractal(const int bar, const double &high[], const double &low[])
{
    if(bar < 2 || bar >= ArraySize(high) - 2)
        return false;
    
    return (high[bar] > high[bar+1] && high[bar] > high[bar+2] &&
            high[bar] > high[bar-1] && high[bar] > high[bar-2]);
}

//+------------------------------------------------------------------+
//| Check for pullback structure                                     |
//+------------------------------------------------------------------+
bool HasPullbackStructure(const int bar, const double &high[], const double &low[], const double &close[])
{
    if(currentWave.fib1Bar == -1)
        return false;
    
    int barsSinceFib1 = currentWave.fib1Bar - bar;
    if(barsSinceFib1 < 3 || barsSinceFib1 > 50)
        return false;
    
    //--- Check for retracement
    double retracementLevel = 0.5;
    double retracementPrice = currentWave.fib0 + (currentWave.fib1 - currentWave.fib0) * retracementLevel;
    
    if(currentWave.direction == 1)
    {
        //--- Upward wave, look for downward pullback
        for(int i = bar; i < currentWave.fib1Bar; i++)
        {
            if(low[i] <= retracementPrice)
                return true;
        }
    }
    else
    {
        //--- Downward wave, look for upward pullback
        for(int i = bar; i < currentWave.fib1Bar; i++)
        {
            if(high[i] >= retracementPrice)
                return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for mini Fib structure                                      |
//+------------------------------------------------------------------+
bool HasMiniFibStructure(const int bar, const double &high[], const double &low[], const double &close[])
{
    //--- Find local high/low after pullback
    int lookback = 20;
    if(bar + lookback >= ArraySize(high))
        lookback = ArraySize(high) - bar - 1;
    
    double localHigh = high[bar];
    double localLow = low[bar];
    int highBar = bar;
    int lowBar = bar;
    
    for(int i = bar; i < bar + lookback && i < ArraySize(high); i++)
    {
        if(high[i] > localHigh)
        {
            localHigh = high[i];
            highBar = i;
        }
        if(low[i] < localLow)
        {
            localLow = low[i];
            lowBar = i;
        }
    }
    
    //--- Check if mini Fib0 -> mini Fib1 structure exists
    double miniRange = MathAbs(localHigh - localLow);
    if(miniRange == 0)
        return false;
    
    //--- Structure exists if we have distinct high and low
    return (localHigh != localLow);
}

//+------------------------------------------------------------------+
//| Confirm Fib1 formation                                           |
//+------------------------------------------------------------------+
bool ConfirmFib1Formation(const int bar, const double &high[], const double &low[], const double &close[])
{
    //--- Confirmation requires price moving in wave direction after STATE4
    if(currentWave.direction == 1)
    {
        return (high[bar] > currentWave.entry);
    }
    else
    {
        return (low[bar] < currentWave.entry);
    }
}

//+------------------------------------------------------------------+
//| Calculate trade levels                                            |
//+------------------------------------------------------------------+
void CalculateTradeLevels(WaveStructure &wave)
{
    double range = MathAbs(wave.fib1 - wave.fib0);
    
    if(wave.direction == 1)
    {
        //--- Upward wave
        wave.entry = wave.fib0 + (range * FIB_0_618);
        wave.sl = wave.fib0 - (range * 0.1);
        wave.tp1 = wave.fib0 + (range * FIB_2_33);
        wave.tp2 = wave.fib0 + (range * FIB_2_618);
        wave.tp3 = wave.fib0 + (range * FIB_4_236);
    }
    else
    {
        //--- Downward wave
        wave.entry = wave.fib0 - (range * FIB_0_618);
        wave.sl = wave.fib0 + (range * 0.1);
        wave.tp1 = wave.fib0 - (range * FIB_2_33);
        wave.tp2 = wave.fib0 - (range * FIB_2_618);
        wave.tp3 = wave.fib0 - (range * FIB_4_236);
    }
}

//+------------------------------------------------------------------+
//| Check if structure failed                                        |
//+------------------------------------------------------------------+
bool StructureFailed(const int bar, const double &high[], const double &low[], const double &close[])
{
    if(currentWave.fib0 == 0)
        return true;
    
    //--- Structure fails if price breaks Fib0 significantly
    double breakLevel = currentWave.fib0 * 0.002; // 0.2% break
    
    if(currentWave.direction == 1)
    {
        if(low[bar] < currentWave.fib0 - breakLevel)
            return true;
    }
    else
    {
        if(high[bar] > currentWave.fib0 + breakLevel)
            return true;
    }
    
    //--- Timeout check
    if(currentWave.fib0Bar != -1)
    {
        int barsSince = currentWave.fib0Bar - bar;
        if(barsSince > 100) // 100 bars timeout
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Draw marker on chart                                             |
//+------------------------------------------------------------------+
void DrawMarker(string name, datetime time, double price, color clr, int code)
{
    if(ObjectCreate(0, name, OBJ_ARROW, 0, time, price))
    {
        ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, 0);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
    }
}

//+------------------------------------------------------------------+
//| Create info panel                                                |
//+------------------------------------------------------------------+
void CreatePanel()
{
    //--- Create panel background
    string bgName = panelPrefix + "BG";
    if(ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0))
    {
        ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, InpPanelX);
        ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, InpPanelY);
        ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 220);
        ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 200);
        ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpPanelBgColor);
        ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, clrGray);
        ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, bgName, OBJPROP_SELECTED, false);
    }
    
    //--- Create title
    string titleName = panelPrefix + "TITLE";
    if(ObjectCreate(0, titleName, OBJ_LABEL, 0, 0, 0))
    {
        ObjectSetString(0, titleName, OBJPROP_TEXT, "TUTTO VISUAL CORE");
        ObjectSetInteger(0, titleName, OBJPROP_COLOR, InpPanelTextColor);
        ObjectSetInteger(0, titleName, OBJPROP_FONTSIZE, InpPanelFontSize + 2);
        ObjectSetString(0, titleName, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, titleName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
        ObjectSetInteger(0, titleName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, titleName, OBJPROP_XDISTANCE, InpPanelX + 10);
        ObjectSetInteger(0, titleName, OBJPROP_YDISTANCE, InpPanelY + 10);
        ObjectSetInteger(0, titleName, OBJPROP_SELECTABLE, false);
    }
    
    //--- Create labels for each data point
    string labels[] = {"STATE", "Direction", "Fib0", "Fib1", "Fib2.33", "Fib2.618", "Fib4.236", "EMA200 Dist"};
    int labelCount = ArraySize(labels);
    
    //--- Adjust panel height based on MTF
    int panelHeight = InpUseMTF ? 280 : 200;
    
    //--- Update panel background size
    string bgName = panelPrefix + "BG";
    if(ObjectFind(0, bgName) >= 0)
    {
        ObjectSetInteger(0, bgName, OBJPROP_YSIZE, panelHeight);
    }
    
    for(int i = 0; i < labelCount; i++)
    {
        string labelName = panelPrefix + "LABEL_" + IntegerToString(i);
        if(ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0))
        {
            ObjectSetString(0, labelName, OBJPROP_TEXT, labels[i] + ":");
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, InpPanelTextColor);
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, InpPanelFontSize);
            ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
            ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
            ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, InpPanelX + 10);
            ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, InpPanelY + 35 + (i * 20));
            ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
        }
        
        string valueName = panelPrefix + "VALUE_" + IntegerToString(i);
        if(ObjectCreate(0, valueName, OBJ_LABEL, 0, 0, 0))
        {
            ObjectSetString(0, valueName, OBJPROP_TEXT, "--");
            ObjectSetInteger(0, valueName, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, valueName, OBJPROP_FONTSIZE, InpPanelFontSize);
            ObjectSetString(0, valueName, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, valueName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            ObjectSetInteger(0, valueName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
            ObjectSetInteger(0, valueName, OBJPROP_XDISTANCE, InpPanelX + 80);
            ObjectSetInteger(0, valueName, OBJPROP_YDISTANCE, InpPanelY + 35 + (i * 20));
            ObjectSetInteger(0, valueName, OBJPROP_SELECTABLE, false);
        }
    }
    
    //--- Create MTF labels if enabled
    if(InpUseMTF)
    {
        string mtfLabels[] = {"M1", "M5", "M15", "H1", "H4", "D1", "W1"};
        for(int i = 0; i < 7; i++)
        {
            string mtfLabelName = panelPrefix + "MTF_LABEL_" + IntegerToString(i);
            if(ObjectCreate(0, mtfLabelName, OBJ_LABEL, 0, 0, 0))
            {
                ObjectSetString(0, mtfLabelName, OBJPROP_TEXT, mtfLabels[i] + ":");
                ObjectSetInteger(0, mtfLabelName, OBJPROP_COLOR, InpPanelTextColor);
                ObjectSetInteger(0, mtfLabelName, OBJPROP_FONTSIZE, InpPanelFontSize - 1);
                ObjectSetString(0, mtfLabelName, OBJPROP_FONT, "Arial");
                ObjectSetInteger(0, mtfLabelName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
                ObjectSetInteger(0, mtfLabelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
                ObjectSetInteger(0, mtfLabelName, OBJPROP_XDISTANCE, InpPanelX + 10);
                ObjectSetInteger(0, mtfLabelName, OBJPROP_YDISTANCE, InpPanelY + 200 + (i * 11));
                ObjectSetInteger(0, mtfLabelName, OBJPROP_SELECTABLE, false);
            }
            
            string mtfValueName = panelPrefix + "MTF_VALUE_" + IntegerToString(i);
            if(ObjectCreate(0, mtfValueName, OBJ_LABEL, 0, 0, 0))
            {
                ObjectSetString(0, mtfValueName, OBJPROP_TEXT, "--");
                ObjectSetInteger(0, mtfValueName, OBJPROP_COLOR, clrAqua);
                ObjectSetInteger(0, mtfValueName, OBJPROP_FONTSIZE, InpPanelFontSize - 1);
                ObjectSetString(0, mtfValueName, OBJPROP_FONT, "Arial");
                ObjectSetInteger(0, mtfValueName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
                ObjectSetInteger(0, mtfValueName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
                ObjectSetInteger(0, mtfValueName, OBJPROP_XDISTANCE, InpPanelX + 50);
                ObjectSetInteger(0, mtfValueName, OBJPROP_YDISTANCE, InpPanelY + 200 + (i * 11));
                ObjectSetInteger(0, mtfValueName, OBJPROP_SELECTABLE, false);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update info panel                                                |
//+------------------------------------------------------------------+
void UpdatePanel(double currentPrice, double currentEMA200)
{
    //--- STATE
    string stateText = "STATE" + IntegerToString(currentWave.state);
    UpdatePanelValue(0, stateText);
    
    //--- Direction
    string dirText = currentWave.direction == 1 ? "UP" : (currentWave.direction == -1 ? "DOWN" : "--");
    UpdatePanelValue(1, dirText);
    
    //--- Fib0
    string fib0Text = currentWave.fib0 != 0 ? DoubleToString(currentWave.fib0, _Digits) : "--";
    UpdatePanelValue(2, fib0Text);
    
    //--- Fib1
    string fib1Text = currentWave.fib1 != 0 ? DoubleToString(currentWave.fib1, _Digits) : "--";
    UpdatePanelValue(3, fib1Text);
    
    //--- Fib2.33
    string fib2_33Text = currentWave.fib2_33 != 0 ? DoubleToString(currentWave.fib2_33, _Digits) : "--";
    UpdatePanelValue(4, fib2_33Text);
    
    //--- Fib2.618
    string fib2_618Text = currentWave.fib2_618 != 0 ? DoubleToString(currentWave.fib2_618, _Digits) : "--";
    UpdatePanelValue(5, fib2_618Text);
    
    //--- Fib4.236
    string fib4_236Text = currentWave.fib4_236 != 0 ? DoubleToString(currentWave.fib4_236, _Digits) : "--";
    UpdatePanelValue(6, fib4_236Text);
    
    //--- EMA200 Distance
    double emaDist = 0;
    if(currentEMA200 != 0)
    {
        emaDist = ((currentPrice - currentEMA200) / currentEMA200) * 100;
    }
    string emaDistText = DoubleToString(emaDist, 3) + "%";
    UpdatePanelValue(7, emaDistText);
    
    //--- Update MTF EMA200 distances if enabled
    if(InpUseMTF)
    {
        for(int i = 0; i < 7; i++)
        {
            if(ArraySize(mtfEma200Buffer[i]) > 0 && mtfEma200Buffer[i][0] != 0)
            {
                double mtfDist = ((currentPrice - mtfEma200Buffer[i][0]) / mtfEma200Buffer[i][0]) * 100;
                string mtfDistText = DoubleToString(mtfDist, 2) + "%";
                UpdateMTFValue(i, mtfDistText);
            }
            else
            {
                UpdateMTFValue(i, "--");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update panel value                                               |
//+------------------------------------------------------------------+
void UpdatePanelValue(int index, string value)
{
    string valueName = panelPrefix + "VALUE_" + IntegerToString(index);
    if(ObjectFind(0, valueName) >= 0)
    {
        ObjectSetString(0, valueName, OBJPROP_TEXT, value);
    }
}

//+------------------------------------------------------------------+
//| Update MTF panel value                                           |
//+------------------------------------------------------------------+
void UpdateMTFValue(int index, string value)
{
    string valueName = panelPrefix + "MTF_VALUE_" + IntegerToString(index);
    if(ObjectFind(0, valueName) >= 0)
    {
        ObjectSetString(0, valueName, OBJPROP_TEXT, value);
    }
}

//+------------------------------------------------------------------+
//| Delete panel objects                                             |
//+------------------------------------------------------------------+
void DeletePanel()
{
    ObjectsDeleteAll(0, panelPrefix);
}

//+------------------------------------------------------------------+
