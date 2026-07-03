#property copyright   "TUTTO STATE MINIMAL"
#property version     "3.00"
#property indicator_chart_window
#property indicator_plots   0
#property indicator_buffers 0

#define STATE0 0
#define STATE1 1
#define STATE2 2
#define STATE3 3
#define STATE4 4
#define STATE5 5

string OBJ_NAME = "TUTTO_STATE_MINIMAL_BG";

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

void ResizeBackground()
  {
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_XSIZE, (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS));
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_YSIZE, (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS));
  }

int OnInit()
  {
   ObjectCreate(0, OBJ_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_XDISTANCE, 0);
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_BACK,      true);
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_BGCOLOR,   clrGray);
   ResizeBackground();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectDelete(0, OBJ_NAME);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      ResizeBackground();
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

   int state = ComputeState(open, high, low, close, rates_total);
   ObjectSetInteger(0, OBJ_NAME, OBJPROP_BGCOLOR, MapStateToColor(state));
   ChartRedraw(0);
   return rates_total;
  }