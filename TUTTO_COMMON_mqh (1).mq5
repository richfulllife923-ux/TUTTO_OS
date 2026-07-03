//+------------------------------------------------------------------+
//| TUTTO_COMMON_mqh.mq5                                             |
//| STATE indicator — v4.00 (UI layer refactor)                      |
//|                                                                   |
//| LOGIC UNCHANGED from v3.00: ComputeState() and MapStateToColor()  |
//| are byte-identical to the previous version.                       |
//|                                                                   |
//| VISUALS CHANGED: previously painted the ENTIRE chart background   |
//| with the state color (Rule #1 violation). Now shows only a small  |
//| corner panel plus a thin (2px) colored border — price is never    |
//| covered.                                                          |
//+------------------------------------------------------------------+
#property copyright   "TUTTO STATE"
#property version     "4.00"
#property indicator_chart_window
#property indicator_plots   0
#property indicator_buffers 0

#include <TUTTO/TUTTO_UI_ObjectManager.mqh>
#include <TUTTO/TUTTO_UI_Panel.mqh>
#include <TUTTO/TUTTO_UI_Markers.mqh>

//====================================================================
// LOGIC (unchanged from v3.00)
//====================================================================
#define STATE0 0
#define STATE1 1
#define STATE2 2
#define STATE3 3
#define STATE4 4
#define STATE5 5

color MapStateToColor(int state)
  {
   switch(state)
     {
      case STATE0: return clrGray;
      case STATE1: return clrBlue;
      case STATE2: return clrCyan;
      case STATE3: return clrGreen;
      case STATE4: return clrOrange;
      case STATE5: return clrRed;
     }
   return clrGray;
  }

string StateLabel(int state)
  {
   switch(state)
     {
      case STATE0: return "S0 · QUIET";
      case STATE1: return "S1 · BUILD";
      case STATE2: return "S2 · MOVE";
      case STATE3: return "S3 · STRONG";
      case STATE4: return "S4 · TREND";
      case STATE5: return "S5 · REVERSAL";
     }
   return "S? · UNKNOWN";
  }

int ComputeState(const double &open[], const double &high[],
                 const double &low[], const double &close[], int total)
  {
   if(total < 2) return STATE0;
   int i = total - 1;
   int p = total - 2;

   double bodyCur  = MathAbs(close[i] - open[i]);
   double rangeCur = high[i] - low[i];
   double direction = close[i] - close[p];

   if(rangeCur <= 0) return STATE0;

   double ratio = bodyCur / rangeCur;

   if(ratio < 0.2) return STATE0;
   if(ratio < 0.4) return STATE1;
   if(ratio < 0.6) return STATE2;
   if(ratio < 0.8) return STATE3;

   double bodyPrevDir = close[p] - open[p];
   bool oppDir = (direction > 0 && bodyPrevDir < 0) || (direction < 0 && bodyPrevDir > 0);

   if(oppDir) return STATE5;
   return STATE4;
  }

//====================================================================
// UI (new)
//====================================================================
input bool ShowStatePanel  = true;   // corner panel
input bool ShowStateBorder = true;   // thin chart-edge border

CTuttoObjectManager g_mgr;

int OnInit()
  {
   g_mgr.Init("STATE");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   g_mgr.DeleteAll();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // border strips are corner-anchored so they don't need manual resize,
   // but width/height of the strips themselves must follow chart size
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      // no-op: TuttoMarkers_Border() is re-issued every OnCalculate anyway
     }
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
  {
   if(rates_total < 2) return 0;

   int   state = ComputeState(open, high, low, close, rates_total);
   color clr   = MapStateToColor(state);

   if(ShowStatePanel)
     {
      TuttoPanelLine lines[];
      ArrayResize(lines, 1);
      lines[0] = TuttoPanelLine_Make(StateLabel(state), clr);
      TuttoPanel_Show(g_mgr, "TUTTO STATE", lines, clr);
     }
   else
      TuttoPanel_Hide(g_mgr);

   if(ShowStateBorder)
      TuttoMarkers_Border(g_mgr, clr);
   else
      TuttoMarkers_ClearBorder(g_mgr);

   ChartRedraw(0);
   return rates_total;
  }
