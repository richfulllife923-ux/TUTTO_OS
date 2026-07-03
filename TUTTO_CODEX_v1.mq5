//====================================================
// TUTTO CODEX Signal Engine v2.0 COMPLETE
// Adaptive Structural Observation OS
//====================================================

#property strict
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   5

//====================================================
// PLOTS
//====================================================

#property indicator_label1  "BUY"
#property indicator_label2  "SELL"
#property indicator_label3  "S3"
#property indicator_label4  "S25"
#property indicator_label5  "OMEGA"

#property indicator_type1   DRAW_ARROW
#property indicator_type2   DRAW_ARROW
#property indicator_type3   DRAW_ARROW
#property indicator_type4   DRAW_ARROW
#property indicator_type5   DRAW_LINE

#property indicator_color1  clrLime
#property indicator_color2  clrRed
#property indicator_color3  clrDodgerBlue
#property indicator_color4  clrGold
#property indicator_color5  clrAqua

#property indicator_width5  2

//====================================================
// INPUTS
//====================================================

input int    SwingLookback  = 48;

input bool   EnableAlert    = true;
input bool   EnablePush     = false;
input bool   EnableComment  = true;
input bool   EnableBGColor  = true;
input bool   EnableVelocity = true;

input string Symbol_M2      = "NAS100";
input string Symbol_M3      = "XAUUSD";

input ENUM_TIMEFRAMES TF_M2 = PERIOD_H1;
input ENUM_TIMEFRAMES TF_M3 = PERIOD_H1;

//====================================================
// CONSTANTS
//====================================================

#define ALPHA   0.618
#define BETA    0.382

#define OMEGA_1 0.15
#define OMEGA_2 0.35
#define OMEGA_3 0.618

//====================================================
// BUFFERS
//====================================================

double bufBuy[];
double bufSell[];
double bufS3[];
double bufS25[];
double bufOmega[];

//====================================================
// GLOBALS
//====================================================

string   g_last_state = "";
datetime g_last_bar   = 0;
datetime g_last_alert = 0;

double   g_last_omega = 0.0;

//====================================================
// INIT
//====================================================

int OnInit()
{
   SetIndexBuffer(0, bufBuy,   INDICATOR_DATA);
   SetIndexBuffer(1, bufSell,  INDICATOR_DATA);
   SetIndexBuffer(2, bufS3,    INDICATOR_DATA);
   SetIndexBuffer(3, bufS25,   INDICATOR_DATA);
   SetIndexBuffer(4, bufOmega, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 241);
   PlotIndexSetInteger(1, PLOT_ARROW, 242);
   PlotIndexSetInteger(2, PLOT_ARROW, 108);
   PlotIndexSetInteger(3, PLOT_ARROW, 159);

   return(INIT_SUCCEEDED);
}

//====================================================
// NORMALIZED FIELD
//====================================================

double CalcF(double price,double hi,double lo)
{
   double d = hi - lo;

   if(d <= 0.0)
      return 0.0;

   return (price - lo) / d;
}

//====================================================
// OMEGA
//====================================================

double CalcOmega(double f1,double f2,double f3)
{
   return f1 - ALPHA*f2 - BETA*f3;
}

//====================================================
// STATE
//====================================================

string StateStr(int s)
{
   if(s==0) return "S0 PRE";
   if(s==1) return "S1 RECOGNITION";
   if(s==2) return "S2 ACCUMULATION";
   if(s==3) return "S3 ACTIVATION";

   return "?";
}

//====================================================
// BG COLOR
//====================================================

void SetBGColor(int state)
{
   if(!EnableBGColor)
      return;

   color c = clrBlack;

   switch(state)
   {
      case 0: c = C'20,20,20'; break;
      case 1: c = C'20,60,20'; break;
      case 2: c = C'120,120,20'; break;
      case 3: c = C'120,20,20'; break;
   }

   ChartSetInteger(0, CHART_COLOR_BACKGROUND, c);
}

//====================================================
// MAIN
//====================================================

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
   if(rates_total < SwingLookback + 10)
      return 0;

   ArraySetAsSeries(close,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(time,true);

   //--------------------------------------------------
   // CURRENT BAR
   //--------------------------------------------------

   int i = 0;

   //--------------------------------------------------
   // MAIN MARKET
   //--------------------------------------------------

   int hi_idx = iHighest(NULL,0,MODE_HIGH,SwingLookback,1);
   int lo_idx = iLowest(NULL,0,MODE_LOW,SwingLookback,1);

   double anc_high = high[hi_idx];
   double anc_low  = low[lo_idx];

   double f1 = CalcF(close[i], anc_high, anc_low);

   //--------------------------------------------------
   // CROSS MARKET
   //--------------------------------------------------

   double m2_close = iClose(Symbol_M2, TF_M2, i);
   double m3_close = iClose(Symbol_M3, TF_M3, i);

   double f2 = f1;
   double f3 = f1;

   if(m2_close > 0)
   {
      f2 = CalcF(
         m2_close,
         iHigh(Symbol_M2,TF_M2,
         iHighest(Symbol_M2,TF_M2,MODE_HIGH,SwingLookback,i)),
         iLow(Symbol_M2,TF_M2,
         iLowest(Symbol_M2,TF_M2,MODE_LOW,SwingLookback,i))
      );
   }

   if(m3_close > 0)
   {
      f3 = CalcF(
         m3_close,
         iHigh(Symbol_M3,TF_M3,
         iHighest(Symbol_M3,TF_M3,MODE_HIGH,SwingLookback,i)),
         iLow(Symbol_M3,TF_M3,
         iLowest(Symbol_M3,TF_M3,MODE_LOW,SwingLookback,i))
      );
   }

   //--------------------------------------------------
   // OMEGA ENGINE
   //--------------------------------------------------

   double omega_raw = CalcOmega(f1,f2,f3);

   double omega =
      0.7 * omega_raw +
      0.3 * g_last_omega;

   double velocity =
      omega - g_last_omega;

   if(MathAbs(velocity) < 0.01)
      velocity = 0;

   bufOmega[i] = omega;

   //--------------------------------------------------
   // STATE ENGINE
   //--------------------------------------------------

   int state = 0;

   if(omega >= OMEGA_3)
      state = 3;
   else if(omega >= OMEGA_2)
      state = 2;
   else if(omega >= OMEGA_1)
      state = 1;

   string cur_state = StateStr(state);

   //--------------------------------------------------
   // BG
   //--------------------------------------------------

   SetBGColor(state);

   //--------------------------------------------------
   // SIGNALS
   //--------------------------------------------------

   bufBuy[i]  = EMPTY_VALUE;
   bufSell[i] = EMPTY_VALUE;
   bufS3[i]   = EMPTY_VALUE;
   bufS25[i]  = EMPTY_VALUE;

   if(g_last_omega < OMEGA_2 &&
      omega >= OMEGA_2)
   {
      bufBuy[i] = low[i] - 20 * _Point;
   }

   if(g_last_omega >= OMEGA_2 &&
      omega < OMEGA_2)
   {
      bufSell[i] = high[i] + 20 * _Point;
   }

   if(omega >= OMEGA_3)
   {
      bufS3[i] = high[i] + 40 * _Point;
   }

   //--------------------------------------------------
   // DIVERGENCE
   //--------------------------------------------------

   string divergence = "NONE";

   if(f1 < f2 && velocity < 0)
      divergence = "BTC WEAKNESS";

   if(f1 > f2 && velocity > 0)
      divergence = "RISK EXPANSION";

   //--------------------------------------------------
   // ALERT ENGINE
   //--------------------------------------------------

   if(time[0] != g_last_bar)
   {
      g_last_bar = time[0];

      if(cur_state != g_last_state)
      {
         string msg =
            "[TUTTO] " +
            cur_state +
            " | Omega=" +
            DoubleToString(omega,4);

         if(TimeCurrent() - g_last_alert > 60)
         {
            if(EnableAlert)
               Alert(msg);

            if(EnablePush)
               SendNotification(msg);

            Print(msg);

            g_last_alert = TimeCurrent();
         }

         g_last_state = cur_state;
      }
   }

   //--------------------------------------------------
   // HUD
   //--------------------------------------------------

   if(EnableComment)
   {
      string icon = "⚪";

      if(state==1) icon="🟢";
      if(state==2) icon="🟡";
      if(state==3) icon="🔴";

      string txt =
         "TUTTO CODEX v2.0 COMPLETE\n"
         "========================\n\n"

         "PHASE\n"
         + icon + " " + cur_state + "\n\n"

         "OMEGA\n"
         + DoubleToString(omega,4) + "\n\n"

         "VELOCITY\n"
         + DoubleToString(velocity,4) + "\n\n"

         "PATHWAY\n"
         + divergence + "\n\n"

         "MARKET FIELD\n"
         "MAIN : " + DoubleToString(f1,4) + "\n"
         "M2   : " + DoubleToString(f2,4) + "\n"
         "M3   : " + DoubleToString(f3,4) + "\n\n"

         "THRESHOLDS\n"
         "0.15 / 0.35 / 0.618\n\n"

         "ENGINE\n"
         "LIVE TICK MODE\n\n"

         "TIMEFRAME\n"
         + EnumToString(_Period);

      Comment(txt);
   }

   //--------------------------------------------------
   // SAVE
   //--------------------------------------------------

   g_last_omega = omega;

   return(rates_total);
}konnpairu sitaradousimasu ?
