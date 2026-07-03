//+------------------------------------------------------------------+
//| TUTTO_MASTER_OS_v3_2_FIXED.mq5  (UI layer refactor -> v3.3)      |
//|                                                                   |
//| LOGIC UNCHANGED: GetPhase(), SweepUp(), SweepDown(), the ENTRY    |
//| RULES block, and all buffer/arrow output are byte-identical to    |
//| v3.2. Only the info display changed: the multi-line Comment()     |
//| block (which duplicated text already shown elsewhere on the       |
//| chart) is replaced by a call into the shared corner panel.        |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

//---------------- PLOT 1 MA200
#property indicator_label1  "MA200"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  2

//---------------- PLOT 2 EMA50
#property indicator_label2  "EMA50"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  1

//---------------- PLOT 3 BUY
#property indicator_label3  "BUY"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime

//---------------- PLOT 4 SELL
#property indicator_label4  "SELL"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed

#include <TUTTO/TUTTO_UI_ObjectManager.mqh>
#include <TUTTO/TUTTO_UI_Panel.mqh>
#include <TUTTO/TUTTO_UI_Style.mqh>
// Requires TUTTO_UI_VERSION: TUTTO UI LAYER v1.3 (dot-first STATE, Renderer+ObjectManager gatekeeper) (must match every file in Include/TUTTO/)

//--- buffers
double ma200[];
double ema50[];
double buy[];
double sell[];

//--- handles
int h_ma200;
int h_ema50;
int h_atr;

CTuttoObjectManager g_mgr;

//+------------------------------------------------------------------+
//| PHASE ENUM  (unchanged)                                          |
//+------------------------------------------------------------------+
enum TUTTO_PHASE
{
   PHASE_EXHAUSTION = 0,
   PHASE_AUTHENTICATION,
   PHASE_DISTRIBUTION,
   PHASE_RELEASE,
   PHASE_EXPANSION,
   PHASE_COMPRESSION
};

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, ma200, INDICATOR_DATA);
   SetIndexBuffer(1, ema50, INDICATOR_DATA);
   SetIndexBuffer(2, buy, INDICATOR_DATA);
   SetIndexBuffer(3, sell, INDICATOR_DATA);

   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);

   h_ma200 = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE);
   h_ema50 = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
   h_atr   = iATR(_Symbol, PERIOD_CURRENT, 14);

   if(h_ma200 == INVALID_HANDLE || h_ema50 == INVALID_HANDLE || h_atr == INVALID_HANDLE)
      return INIT_FAILED;

   g_mgr.Init("MASTEROS");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| PHASE DETECTION (SAFE MT5)  (unchanged)                          |
//+------------------------------------------------------------------+
TUTTO_PHASE GetPhase(const double &high[], const double &low[])
{
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);

   if(CopyBuffer(h_atr, 0, 0, 1, atr_buf) <= 0)
      return PHASE_AUTHENTICATION;

   double atr = atr_buf[0];

   double range = high[0] - low[0];

   if(range > atr * 1.8)
      return PHASE_EXPANSION;

   if(range < atr * 0.8)
      return PHASE_COMPRESSION;

   return PHASE_AUTHENTICATION;
}

//+------------------------------------------------------------------+
//| SWEEP LOGIC  (unchanged)                                         |
//+------------------------------------------------------------------+
bool SweepUp(const double &high[], const double &close[])
{
   return (high[1] > high[2] && close[1] < high[2]);
}

bool SweepDown(const double &low[], const double &close[])
{
   return (low[1] < low[2] && close[1] > low[2]);
}

//+------------------------------------------------------------------+
//| UI: map phase -> label/color for the shared panel only.           |
//| This is presentation-only; it does not feed back into any signal. |
//+------------------------------------------------------------------+
string PhaseLabel(TUTTO_PHASE phase)
{
   switch(phase)
   {
      case PHASE_EXPANSION:     return "EXP";
      case PHASE_COMPRESSION:   return "COMP";
      case PHASE_AUTHENTICATION:return "AUTH";
      default:                  return "OTH";
   }
}

color PhaseColor(TUTTO_PHASE phase)
{
   switch(phase)
   {
      case PHASE_EXPANSION:      return TUTTO_ClrBullish;
      case PHASE_COMPRESSION:    return TUTTO_ClrWarning;
      case PHASE_AUTHENTICATION: return TUTTO_ClrNeutral;
      default:                   return TUTTO_ClrCalm;
   }
}

//+------------------------------------------------------------------+
//| MAIN                                                             |
//+------------------------------------------------------------------+
int OnCalculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[]
)
{
   if(rates_total < 200)
      return 0;

   //--- MA / EMA
   if(CopyBuffer(h_ma200, 0, 0, rates_total, ma200) <= 0) return 0;
   if(CopyBuffer(h_ema50, 0, 0, rates_total, ema50) <= 0) return 0;

   //--- reset arrows
   for(int i=0;i<rates_total;i++)
   {
      buy[i]  = EMPTY_VALUE;
      sell[i] = EMPTY_VALUE;
   }

   //--- phase
   TUTTO_PHASE phase = GetPhase(high, low);

   int i = 1; // last closed candle

   bool trendUp   = close[i] > ma200[i];
   bool trendDown = close[i] < ma200[i];

   bool sweepUp   = SweepUp(high, close);
   bool sweepDown = SweepDown(low, close);

   // compression (ATR proxy safe version)
   double range = high[i] - low[i];
   double prevRange = high[i+1] - low[i+1];
   bool compression = (range < prevRange * 0.8);

   bool buySignal  = false;
   bool sellSignal = false;

   // ENTRY RULES
   if(trendUp && sweepDown && compression && phase == PHASE_COMPRESSION)
      buySignal = true;

   if(trendDown && sweepUp && compression && phase == PHASE_COMPRESSION)
      sellSignal = true;

   //--- draw arrows
   if(buySignal)
      buy[i] = low[i] - (Point()*10);

   if(sellSignal)
      sell[i] = high[i] + (Point()*10);

   //--- STATE-tier indicator: dot + single short code (buy/sell state
   //--- is already visible via the arrow buffers, no need to repeat it)
   TuttoState_Show(g_mgr, PhaseColor(phase), PhaseLabel(phase));

   return rates_total;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_mgr.DeleteAll();
}
