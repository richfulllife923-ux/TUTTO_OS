//+------------------------------------------------------------------+
//| TUTTO_PRO_TRADING_ENGINE_v5.mq5  (UI layer refactor)              |
//|                                                                    |
//| LOGIC UNCHANGED: RCI(), GetRCI(), and the entire scoring/entry     |
//| loop in OnCalculate are byte-identical to v5. This file previously|
//| had almost no on-chart text (just Alert() + two arrow buffers) so |
//| the only addition is a minimal shared panel, for consistency with |
//| the other TUTTO indicators — no logic path was touched.           |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1 "BUY"
#property indicator_label2 "SELL"
#property indicator_type1 DRAW_ARROW
#property indicator_type2 DRAW_ARROW
#property indicator_color1 Lime
#property indicator_color2 Red

#include <TUTTO/TUTTO_UI_ObjectManager.mqh>
#include <TUTTO/TUTTO_UI_Panel.mqh>
#include <TUTTO/TUTTO_UI_Style.mqh>
// Requires TUTTO_UI_VERSION: TUTTO UI LAYER v1.3 (dot-first STATE, Renderer+ObjectManager gatekeeper) (must match every file in Include/TUTTO/)

double buyBuffer[];
double sellBuffer[];

datetime last_signal = 0;

CTuttoObjectManager g_mgr;
input bool ShowEnginePanel = true;

//====================================================
// RCI CORE  (unchanged)
//====================================================
double RCI(const double &src[], int period, int shift)
{
   double d = 0;

   for(int i=0;i<period;i++)
   {
      double rank_p = 1;

      for(int j=0;j<period;j++)
         if(src[shift+j] > src[shift+i])
            rank_p++;

      double rank_t = i+1;

      d += MathPow(rank_t - rank_p,2);
   }

   return (1.0 - (6.0*d)/(period*(period*period-1.0)))*100.0;
}

//====================================================
// MTF RCI FETCH  (unchanged)
//====================================================
double GetRCI(ENUM_TIMEFRAMES tf, int period)
{
   MqlRates rates[];
   ArraySetAsSeries(rates,true);

   if(CopyRates(_Symbol,tf,0,period+5,rates) < period)
      return 0;

   double src[];

   ArrayResize(src,period);
   ArraySetAsSeries(src,true);

   for(int i=0;i<period;i++)
      src[i] = rates[i].close;

   return RCI(src,period,0);
}

//====================================================
int OnInit()
{
   SetIndexBuffer(0,buyBuffer);
   SetIndexBuffer(1,sellBuffer);
   g_mgr.Init("PROENGINE");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   g_mgr.DeleteAll();
}

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
   if(rates_total < 200)
      return 0;

   int limit = MathMin(rates_total-2,200);

   //====================================================
   // MTF STRUCTURE  (unchanged)
   //====================================================
   double rci_1m_s  = GetRCI(PERIOD_M1,9);
   double rci_1m_m  = GetRCI(PERIOD_M1,26);

   double rci_5m_s  = GetRCI(PERIOD_M5,9);
   double rci_5m_m  = GetRCI(PERIOD_M5,26);

   double rci_1h_s  = GetRCI(PERIOD_H1,9);
   double rci_1h_m  = GetRCI(PERIOD_H1,26);

   //====================================================
   // MTF ALIGNMENT SCORE  (unchanged)
   //====================================================
   double mtf_align =
      MathAbs(rci_1m_s - rci_5m_s) +
      MathAbs(rci_5m_s - rci_1h_s) +
      MathAbs(rci_1m_m - rci_5m_m);

   bool mtf_sync = (mtf_align < 35);      // important filter
   bool mtf_break = (mtf_align > 120);    // collapse state

   bool any_signal_this_bar = false;

   //====================================================
   // LOOP  (unchanged)
   //====================================================
   for(int i=limit;i>=1;i--)
   {
      buyBuffer[i] = EMPTY_VALUE;
      sellBuffer[i]= EMPTY_VALUE;

      //================================================
      // LOCAL RCI (1m)
      //================================================
      double rci_s = RCI(close,9,i);
      double rci_m = RCI(close,26,i);
      double rci_l = RCI(close,52,i);

      double sync =
         MathAbs(rci_s-rci_m)+MathAbs(rci_m-rci_l);

      bool strong = (sync > 120);
      bool weak   = (sync < 25);

      //================================================
      // PRESSURE VECTOR
      //================================================
      double pressure = (rci_s - rci_l);
      pressure *= (1.0 + sync*0.01);

      //================================================
      // TREND
      //================================================
      bool up = (rci_s>rci_m && rci_m>rci_l);
      bool dn = (rci_s<rci_m && rci_m<rci_l);

      //================================================
      // FAKE BREAK FILTER
      //================================================
      bool valid_break =
         close[i+2] > close[i+3] &&
         close[i+1] > close[i+2] &&
         close[i]   < close[i+1];

      //================================================
      // GLOBAL CONDITION
      //================================================
      bool global_ok =
         mtf_sync &&
         !mtf_break &&
         strong;

      //================================================
      // ENTRY LOGIC
      //================================================
      bool buy =
         global_ok &&
         valid_break &&
         up &&
         pressure < -40;

      bool sell =
         global_ok &&
         valid_break &&
         dn &&
         pressure > 40;

      //================================================
      // OUTPUT
      //================================================
      if(buy)
      {
         buyBuffer[i] = low[i] - 10*_Point;
         any_signal_this_bar = true;

         if(TimeCurrent()-last_signal > 60)
         {
            Alert("TUTTO v5 BUY (MTF CONFIRMED)");
            last_signal = TimeCurrent();
         }
      }

      if(sell)
      {
         sellBuffer[i] = high[i] + 10*_Point;
         any_signal_this_bar = true;

         if(TimeCurrent()-last_signal > 60)
         {
            Alert("TUTTO v5 SELL (MTF CONFIRMED)");
            last_signal = TimeCurrent();
         }
      }
   }

   //--- minimal panel: MTF sync status only, replaces nothing (there was
   //--- no prior on-chart text) — purely additive, for cross-indicator consistency
   color accent = mtf_break ? TUTTO_ClrCritical : (mtf_sync ? TUTTO_ClrBullish : TUTTO_ClrWarning);
   if(ShowEnginePanel)
      TuttoState_Show(g_mgr, accent, DoubleToString(mtf_align, 0));
   else
      TuttoState_Show(g_mgr, accent);   // dot only

   return rates_total;
}
