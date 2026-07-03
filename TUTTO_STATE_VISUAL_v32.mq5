//+------------------------------------------------------------------+
//| TUTTO_STATE_VISUAL v3.2 FULL INTEGRATED                         |
//| State Machine: Swing→Fib→MA→RCI→AUTH→Signal                   |
//| Compile: 0 errors 0 warnings / No repaint / MQL5 only          |
//+------------------------------------------------------------------+
#property copyright   "TUTTO STATE VISUAL v3.2"
#property version     "3.20"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3

#property indicator_label2  "SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3

//+------------------------------------------------------------------+
// INPUT
//+------------------------------------------------------------------+
input int    EMA_Period   = 200;
input int    RCI_Period   = 25;
input int    Fractal_Left = 2;
input double ATR_Mult     = 1.5;
input bool   ShowFibo     = true;

//+------------------------------------------------------------------+
// STATE ENUM
//+------------------------------------------------------------------+
enum AUTH_STATE { AUTH_NONE, AUTH_PENDING, AUTH_REAL };
enum MARKET_STATE { MS_BULL, MS_BEAR, MS_NEUTRAL };

//+------------------------------------------------------------------+
// BUFFERS
//+------------------------------------------------------------------+
double BuyBuf[];
double SellBuf[];

//+------------------------------------------------------------------+
// HANDLES
//+------------------------------------------------------------------+
int hEMA  = INVALID_HANDLE;
int hATR  = INVALID_HANDLE;

//+------------------------------------------------------------------+
// SWING LOCK STRUCTURE
//+------------------------------------------------------------------+
struct SwingLock
  {
   bool     locked;
   double   high;
   double   low;
   datetime high_time;
   datetime low_time;
   int      high_bar;
   int      low_bar;
  };

SwingLock g_swing;

//+------------------------------------------------------------------+
// GLOBALS
//+------------------------------------------------------------------+
string   TUTTO_FIBO_NAME = "TUTTO_FIBO";
string   OBJ_PFX  = "TUTTO_SIG_";
datetime g_last_bar = 0;

//+------------------------------------------------------------------+
// OnInit
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   hEMA = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(hEMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
      return INIT_FAILED;

   g_swing.locked = false;
   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO STATE v3.2");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
// OnDeinit
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hEMA);
   IndicatorRelease(hATR);
   SafeDelete(TUTTO_FIBO_NAME);
   ObjectsDeleteAll(0, OBJ_PFX);
   DeleteUIObjects();
  }

//+------------------------------------------------------------------+
// UTIL: 安全なオブジェクト削除
//+------------------------------------------------------------------+
void SafeDelete(string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

//+------------------------------------------------------------------+
// BLOCK 1: RCI計算(スピアマン順位相関)
// idx=対象インデックス(直近=rates_total-1を0として時系列降順)
//+------------------------------------------------------------------+
double CalcRCI(const double &close[], int idx, int period, int total)
  {
   if(idx < period - 1 || idx >= total) return 0.0;
   double d2 = 0.0;
   for(int i = 0; i < period; i++)
     {
      int ci = idx - i;
      if(ci < 0 || ci >= total) return 0.0;
      double rt = (double)(i + 1); // 時間順位(新しい=1)
      double rp = 1.0;
      for(int j = 0; j < period; j++)
        {
         int cj = idx - j;
         if(cj < 0 || cj >= total) continue;
         if(close[cj] < close[ci]) rp++;
        }
      double d = rt - rp;
      d2 += d * d;
     }
   double n = (double)period;
   return (1.0 - 6.0 * d2 / (n * (n * n - 1.0))) * 100.0;
  }

//+------------------------------------------------------------------+
// BLOCK 2: Market Structure スウィング検出
// Fractalベース廃止 → HH/HL / LH/LL 構造ベース
//
// 構造高値(Structure High / SH):
//   ある高値の後に、直近N本の安値を下回る足が出現 → そのN本前の高値を確定SHとする
//   = 「その高値を超えられずに反落した」ことで構造的に確定
//
// 構造安値(Structure Low / SL):
//   ある安値の後に、直近N本の高値を上回る足が出現 → そのN本前の安値を確定SLとする
//   = 「その安値を割れずに反発した」ことで構造的に確定
//
// BUY Fib:  最新SL(=0) → 直近SH(=1) → 拡張
// SELL Fib: 最新SH(=0) → 直近SL(=1) → 拡張
//
// リペイント防止: bar_start-1 以前の確定バーのみ参照
//+------------------------------------------------------------------+
bool DetectSwing(const double &high[], const double &low[],
                 const double &close[], const datetime &time[],
                 int bar_start, int total,
                 double atr_val, int direction)
  {
   // 最低必要本数: 構造確定に SW_CONFIRM本の後続確認が必要
   int SW  = Fractal_Left;   // 構造確認本数(inputを流用)
   int req = SW * 4 + 2;
   if(bar_start < req || total < req) return false;

   // 検索対象: bar_start-1 まで(未確定バーを除外)
   int search_end = bar_start - 1;

   //--- 構造高値リスト収集(最新2個取得)
   // 判定: high[i]が直後SW本の安値を全て上回っており
   //       かつ直後SW本の中に high[i]より高い値がない
   //       → その後 price が high[i] を超えずに下落 = 構造的高値として確定
   int   sh_bar[2]; sh_bar[0]=-1; sh_bar[1]=-1;
   double sh_val[2]; sh_val[0]=0; sh_val[1]=0;
   int   sh_count=0;

   for(int i = search_end - SW; i >= SW && sh_count < 2; i--)
     {
      if(i+SW >= total) continue;
      // high[i]が前後SW本の中で最高値か
      bool is_sh = true;
      for(int k=1; k<=SW; k++)
        {
         if(i-k<0 || i+k>=total){ is_sh=false; break; }
         // 直前SW本に高値が高いものがあれば構造的高値ではない
         if(high[i-k] >= high[i]){ is_sh=false; break; }
        }
      if(!is_sh) continue;
      // 直後SW本で安値が更新されている(その高値の後に反落確定)
      bool drop_confirmed = false;
      double ref_low = low[i];
      for(int k=1; k<=SW; k++)
        {
         if(i+k>=total) break;
         if(low[i+k] < ref_low){ drop_confirmed=true; break; }
        }
      if(!drop_confirmed) continue;
      sh_bar[sh_count] = i;
      sh_val[sh_count] = high[i];
      sh_count++;
     }

   //--- 構造安値リスト収集(最新2個取得)
   int   sl_bar[2]; sl_bar[0]=-1; sl_bar[1]=-1;
   double sl_val[2]; sl_val[0]=0; sl_val[1]=0;
   int   sl_count=0;

   for(int i = search_end - SW; i >= SW && sl_count < 2; i--)
     {
      if(i+SW >= total) continue;
      bool is_sl = true;
      for(int k=1; k<=SW; k++)
        {
         if(i-k<0 || i+k>=total){ is_sl=false; break; }
         if(low[i-k] <= low[i]){ is_sl=false; break; }
        }
      if(!is_sl) continue;
      bool rise_confirmed = false;
      double ref_high = high[i];
      for(int k=1; k<=SW; k++)
        {
         if(i+k>=total) break;
         if(high[i+k] > ref_high){ rise_confirmed=true; break; }
        }
      if(!rise_confirmed) continue;
      sl_bar[sl_count] = i;
      sl_val[sl_count] = low[i];
      sl_count++;
     }

   if(sh_count < 1 || sl_count < 1) return false;

   int   final_sh = sh_bar[0];  // 最新の構造高値
   double final_sh_v = sh_val[0];
   int   final_sl = sl_bar[0];  // 最新の構造安値
   double final_sl_v = sl_val[0];

   if(final_sh < 0 || final_sl < 0) return false;
   if(final_sh >= total || final_sl >= total) return false;
   if(final_sh_v <= final_sl_v) return false;

   double rng = final_sh_v - final_sl_v;
   if(atr_val > 0 && rng < atr_val * ATR_Mult) return false;

   //--- BUY: 最新SL → 最新SH (SLがSHより古い = 上昇構造)
   //--- SELL: 最新SH → 最新SL (SHがSLより古い = 下降構造)
   int new_sh_bar, new_sl_bar;
   double new_sh_v, new_sl_v;

   if(direction == 1) // BUY: SLが先(古い)でSHが後(新しい) = HH/HL上昇構造
     {
      // SLがSHより過去にある = 上昇構造
      if(final_sl <= final_sh) return false; // final_slはバーインデックス(古い=大きい)
      new_sh_bar = final_sh;
      new_sl_bar = final_sl;
      new_sh_v   = final_sh_v;
      new_sl_v   = final_sl_v;
     }
   else // SELL: SHが先(古い)でSLが後(新しい) = LH/LL下降構造
     {
      if(final_sh <= final_sl) return false; // final_shがfinal_slより過去
      new_sh_bar = final_sh;
      new_sl_bar = final_sl;
      new_sh_v   = final_sh_v;
      new_sl_v   = final_sl_v;
     }

   // Lock済みと同一なら更新しない(リペイント防止)
   if(g_swing.locked &&
      g_swing.high_bar == new_sh_bar &&
      g_swing.low_bar  == new_sl_bar) return false;

   // 新しい親スウィングをロック
   g_swing.locked    = true;
   g_swing.high      = new_sh_v;
   g_swing.low       = new_sl_v;
   g_swing.high_time = time[new_sh_bar];
   g_swing.low_time  = time[new_sl_bar];
   g_swing.high_bar  = new_sh_bar;
   g_swing.low_bar   = new_sl_bar;
   return true;
  }

//+------------------------------------------------------------------+
// BLOCK 3: Fibonacci描画
//+------------------------------------------------------------------+
void DrawFibo(datetime t_low, double price_low,
              datetime t_high, double price_high)
  {
   if(!ShowFibo) return;
   SafeDelete(TUTTO_FIBO_NAME);

   // ObjectCreate第3引数はMQL5標準定数 OBJ_FIBO(enum値)を使用
   if(!ObjectCreate(0, TUTTO_FIBO_NAME, OBJ_FIBO, 0,
                    t_low,  price_low,
                    t_high, price_high)) return;

   // 標準Fibレベル設定
   double levels[] = {0.0, 0.236, 0.382, 0.5, 0.618,
                      0.705, 0.786, 1.0, 1.382, 1.618,
                      2.0, 2.618, 3.236, 4.236};
   int lv_count = ArraySize(levels);
   ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_LEVELS, (long)lv_count);
   for(int k = 0; k < lv_count; k++)
     {
      ObjectSetDouble (0, TUTTO_FIBO_NAME, OBJPROP_LEVELVALUE, k, levels[k]);
      ObjectSetString (0, TUTTO_FIBO_NAME, OBJPROP_LEVELTEXT,  k,
                       DoubleToString(levels[k], 3));
      ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_LEVELCOLOR, k, (long)clrGray);
      ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_LEVELSTYLE, k, (long)STYLE_DOT);
      ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_LEVELWIDTH, k, 1L);
     }
   ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_BACK,       true);
   ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_RAY_RIGHT,  true);
  }

//+------------------------------------------------------------------+
// BLOCK 4: MA状態判定
//+------------------------------------------------------------------+
MARKET_STATE GetMAState(double close_val, double ma_val)
  {
   if(ma_val <= 0) return MS_NEUTRAL;
   if(close_val > ma_val) return MS_BULL;
   if(close_val < ma_val) return MS_BEAR;
   return MS_NEUTRAL;
  }

//+------------------------------------------------------------------+
// BLOCK 5: AUTH判定
// AUTH_REAL: MA一致 + RCI[-80,+80]内
// AUTH_PENDING: MA一致のみ
// AUTH_NONE: 不一致
//+------------------------------------------------------------------+
AUTH_STATE GetAUTH(MARKET_STATE ms, int direction, double rci_val)
  {
   bool ma_ok  = (direction == 1 && ms == MS_BULL) ||
                 (direction ==-1 && ms == MS_BEAR);
   bool rci_ok = (rci_val >= -80.0 && rci_val <= 80.0);

   if(!ma_ok)          return AUTH_NONE;
   if(ma_ok && rci_ok) return AUTH_REAL;
   return AUTH_PENDING;
  }

//+------------------------------------------------------------------+
// BLOCK 6: シグナル矢印描画
//+------------------------------------------------------------------+
void DrawSignalArrow(int direction, datetime bar_time,
                     double price, int bar_idx)
  {
   string name = OBJ_PFX + (direction==1?"BUY":"SELL") +
                 IntegerToString(bar_idx);
   SafeDelete(name);
   if(!ObjectCreate(0, name,
                    (direction==1)?OBJ_ARROW_BUY:OBJ_ARROW_SELL,
                    0, bar_time, price)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,
                    (direction==1)?clrLime:clrRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      3);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,
                    (direction==1)?ANCHOR_TOP:ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
// UI BLOCK: ENTRY / STOP / TP ライン描画
// ロジック変更ゼロ。描画追加のみ。
//+------------------------------------------------------------------+

// 水平ラインを太線で描画
void DrawHLine(string name, double price, color clr, int width, string label_txt)
  {
   SafeDelete(name);
   SafeDelete(name+"_L");
   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     width);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   // ラベル(チャート右端に大文字で表示)
   if(!ObjectCreate(0, name+"_L", OBJ_TEXT, 0,
                    iTime(_Symbol, PERIOD_CURRENT, 0), price)) return;
   ObjectSetString (0, name+"_L", OBJPROP_TEXT,      label_txt);
   ObjectSetInteger(0, name+"_L", OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name+"_L", OBJPROP_FONTSIZE,  11);
   ObjectSetString (0, name+"_L", OBJPROP_FONT,      "Arial Black");
   ObjectSetInteger(0, name+"_L", OBJPROP_ANCHOR,    ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name+"_L", OBJPROP_BACK,      false);
   ObjectSetInteger(0, name+"_L", OBJPROP_SELECTABLE,false);
  }

// シグナル状態ラベル(左上コーナー)
void DrawStateLabel(string state_txt, color clr)
  {
   string name = OBJ_PFX+"STATE";
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, 10);
   ObjectSetString (0,name,OBJPROP_TEXT,      state_txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  18);
   ObjectSetString (0,name,OBJPROP_FONT,      "Arial Black");
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

// BUY/SELL用の大矢印テキストラベル
void DrawBigLabel(string name, datetime t, double price,
                  string txt, color clr, int anchor)
  {
   SafeDelete(name);
   if(!ObjectCreate(0,name,OBJ_TEXT,0,t,price)) return;
   ObjectSetString (0,name,OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  16);
   ObjectSetString (0,name,OBJPROP_FONT,      "Arial Black");
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

// 全UIオブジェクト削除
void DeleteUIObjects()
  {
   string keys[] = {"ENTRY","STOP","TP1","TP2","TP3",
                    "ENTRY_L","STOP_L","TP1_L","TP2_L","TP3_L",
                    "BIG_LBL","STATE"};
   for(int k=0;k<ArraySize(keys);k++)
      SafeDelete(OBJ_PFX+keys[k]);
  }

// シグナル発火時の全UI描画
void DrawTradeUI(int dir, datetime sig_time,
                 double entry, double stop,
                 double tp1, double tp2, double tp3)
  {
   DeleteUIObjects();

   // ENTRY ライン(白・太線2)
   DrawHLine(OBJ_PFX+"ENTRY", entry, clrWhite,    2, "  ENTRY  "+DoubleToString(entry,_Digits));

   // STOP ライン(ダークレッド・太線3)
   DrawHLine(OBJ_PFX+"STOP",  stop,  clrDarkRed,  3, "  STOP   "+DoubleToString(stop,_Digits));

   // TP1 ライン(青・太線2)
   DrawHLine(OBJ_PFX+"TP1",   tp1,   clrDodgerBlue,2,"  TP1    "+DoubleToString(tp1,_Digits));

   // TP2 ライン(紫・太線2)
   DrawHLine(OBJ_PFX+"TP2",   tp2,   clrMediumOrchid,2,"  TP2    "+DoubleToString(tp2,_Digits));

   // TP3 ライン(金・太線2)
   DrawHLine(OBJ_PFX+"TP3",   tp3,   clrGold,     2, "  TP3    "+DoubleToString(tp3,_Digits));

   // BUY/SELL 大文字ラベル(矢印の横)
   if(dir == 1)
     {
      DrawBigLabel(OBJ_PFX+"BIG_LBL", sig_time, entry,
                   "  ▲ REAL BUY", clrLime, ANCHOR_LEFT_UPPER);
      DrawStateLabel("▲ REAL BUY", clrLime);
     }
   else
     {
      DrawBigLabel(OBJ_PFX+"BIG_LBL", sig_time, entry,
                   "  ▼ REAL SELL", clrRed, ANCHOR_LEFT_LOWER);
      DrawStateLabel("▼ REAL SELL", clrRed);
     }
  }

//+------------------------------------------------------------------+
// OnCalculate — 状態機械メインループ
//+------------------------------------------------------------------+
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
   int min_req = EMA_Period + RCI_Period + Fractal_Left * 4 + 10;
   if(rates_total < min_req) return 0;

   //--- EMA・ATRバッファ取得
   double ema[], atr_buf[];
   ArraySetAsSeries(ema,     false);
   ArraySetAsSeries(atr_buf, false);
   if(CopyBuffer(hEMA, 0, 0, rates_total, ema)     < rates_total) return 0;
   if(CopyBuffer(hATR, 0, 0, rates_total, atr_buf) < rates_total) return 0;

   //--- 処理開始インデックス
   int start = (prev_calculated > 1) ? prev_calculated - 1 : min_req;

   //--- ─── 状態機械ループ ───
   for(int i = start; i < rates_total - 1; i++) // 最終バー(未確定)はスキップ
     {
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;

      if(i < min_req) continue;

      double atr_val = (i < rates_total) ? atr_buf[i] : 0.0;

      //--- STATE 1: Swing検出(方向判定はMA状態で決定)
      MARKET_STATE ms = GetMAState(close[i], ema[i]);
      int dir = (ms == MS_BULL) ? 1 : (ms == MS_BEAR) ? -1 : 0;
      if(dir == 0) continue;

      bool swing_new = DetectSwing(high, low, close, time,
                                   i, rates_total, atr_val, dir);

      //--- STATE 2: Fib描画(新Swing確定時のみ)
      if(swing_new && g_swing.locked)
         DrawFibo(g_swing.low_time,  g_swing.low,
                  g_swing.high_time, g_swing.high);

      if(!g_swing.locked) continue;

      //--- STATE 3: RCI計算
      double rci = CalcRCI(close, i, RCI_Period, rates_total);

      //--- STATE 4: AUTH判定
      AUTH_STATE auth = GetAUTH(ms, dir, rci);
      if(auth != AUTH_REAL)
        {
         // FAKE / WAIT 状態表示(最終バー付近のみ更新)
         if(i == rates_total - 2)
           {
            if(auth == AUTH_PENDING)
               DrawStateLabel("◎ WAIT", clrYellow);
            else
               DrawStateLabel("✕ FAKE", clrGray);
           }
         continue;
        }

      //--- STATE 5: Fib帯チェック
      double rng = g_swing.high - g_swing.low;
      if(rng <= 0) continue;
      double fib_lo, fib_hi;
      if(dir == 1) // BUY: 2.330〜2.618帯
        {
         fib_lo = g_swing.low + 2.330 * rng;
         fib_hi = g_swing.low + 2.618 * rng;
        }
      else // SELL: 3.770〜4.236帯
        {
         fib_lo = g_swing.low + 3.770 * rng;
         fib_hi = g_swing.low + 4.236 * rng;
        }
      bool in_zone = (close[i] >= fib_lo && close[i] <= fib_hi);
      if(!in_zone) continue;

      //--- STATE 6: シグナル発火 → バッファとオブジェクト + UI描画
      if(dir == 1)
        {
         BuyBuf[i] = low[i];
         DrawSignalArrow(1, time[i], low[i], i);

         // TP/STOP計算(BUY)
         // STOP = SwingLow(構造崩壊点)
         // ENTRY = 現在終値
         // TP1 = sw_low + 3.236*rng
         // TP2 = sw_low + 4.236*rng
         // TP3 = sw_low + 6.854*rng
         double entry_p = close[i];
         double stop_p  = g_swing.low;
         double tp1_p   = g_swing.low + 3.236 * rng;
         double tp2_p   = g_swing.low + 4.236 * rng;
         double tp3_p   = g_swing.low + 6.854 * rng;
         DrawTradeUI(1, time[i], entry_p, stop_p, tp1_p, tp2_p, tp3_p);
        }
      else
        {
         SellBuf[i] = high[i];
         DrawSignalArrow(-1, time[i], high[i], i);

         // TP/STOP計算(SELL)
         // STOP = SwingHigh(構造崩壊点)
         // TP1 = sw_high - 3.236*rng
         // TP2 = sw_high - 4.236*rng
         // TP3 = sw_high - 6.854*rng
         double entry_p = close[i];
         double stop_p  = g_swing.high;
         double tp1_p   = g_swing.high - 3.236 * rng;
         double tp2_p   = g_swing.high - 4.236 * rng;
         double tp3_p   = g_swing.high - 6.854 * rng;
         DrawTradeUI(-1, time[i], entry_p, stop_p, tp1_p, tp2_p, tp3_p);
        }
     }

   ChartRedraw(0);
   return rates_total;
  }
