#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_label1  "BUY ENTRY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua

#property indicator_label2  "SELL ENTRY"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed

#property indicator_label3  "TP1"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrAqua

#property indicator_label4  "TP2"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGold

#property indicator_label5  "TP3"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed

//================ INPUT =================
input int MA_Period = 200;
input double Score_Threshold = 12.0;

//================ BUFFERS =================
double BuyBuffer[];
double SellBuffer[];
double TP1Buffer[];
double TP2Buffer[];
double TP3Buffer[];

//================ MA HANDLE =================
int maHandle;

//================ STATE =================
enum TUTTO_STATE
{
   STATE_NEUTRAL=0,
   STATE_BUY_BIAS,
   STATE_SELL_BIAS,
   STATE_TRANSITION
};

//================ INIT =================
int OnInit()
{
   SetIndexBuffer(0,BuyBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SellBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,TP1Buffer,INDICATOR_DATA);
   SetIndexBuffer(3,TP2Buffer,INDICATOR_DATA);
   SetIndexBuffer(4,TP3Buffer,INDICATOR_DATA);

   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);

   maHandle = iMA(_Symbol,_Period,MA_Period,0,MODE_SMA,PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

//================ STATE =================
TUTTO_STATE GetState(double b,double s,double th)
{
   double d=b-s;

   if(MathAbs(d)<th*0.2) return STATE_NEUTRAL;
   if(d>0) return (d>th*1.5)?STATE_BUY_BIAS:STATE_TRANSITION;
   return (MathAbs(d)>th*1.5)?STATE_SELL_BIAS:STATE_TRANSITION;
}

//================ MAIN =================
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
   int start=(prev_calculated>0)?prev_calculated-1:50;

   double ma[];

   ArraySetAsSeries(ma,true);
   CopyBuffer(maHandle,0,0,rates_total,ma);

   for(int i=start;i<rates_total-1;i++)
   {
      BuyBuffer[i]=EMPTY_VALUE;
      SellBuffer[i]=EMPTY_VALUE;
      TP1Buffer[i]=EMPTY_VALUE;
      TP2Buffer[i]=EMPTY_VALUE;
      TP3Buffer[i]=EMPTY_VALUE;

      double mav = ma[i];

      double price = close[i];

      double b=0;
      double s=0;

      if(price > mav) b+=5;
      else s+=5;

      TUTTO_STATE st = GetState(b,s,Score_Threshold);

      double diff = b - s;

      bool entry_buy  = (st==STATE_BUY_BIAS  && diff>Score_Threshold*1.2);
      bool entry_sell = (st==STATE_SELL_BIAS && -diff>Score_Threshold*1.2);

      double range = high[i] - low[i];
      if(range<=0) continue;

      double entry = close[i];

      //================ BUY =================
      if(entry_buy)
      {
         BuyBuffer[i] = low[i] - range*0.3;

         TP1Buffer[i] = entry + range*2.33;
         TP2Buffer[i] = entry + range*2.618;
         TP3Buffer[i] = entry + range*3.236;
      }

      //================ SELL =================
      if(entry_sell)
      {
         SellBuffer[i] = high[i] + range*0.3;

         TP1Buffer[i] = entry - range*2.33;
         TP2Buffer[i] = entry - range*2.618;
         TP3Buffer[i] = entry - range*3.236;
      }
   }

   return rates_total;
}