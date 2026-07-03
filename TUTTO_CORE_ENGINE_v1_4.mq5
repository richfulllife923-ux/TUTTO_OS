//+------------------------------------------------------------------+
//|                                      TUTTO_CORE_ENGINE_v14.mq5  |
//|              TUTTO CORE ARCHITECTURE v1.4 State Machine Engine |
//+------------------------------------------------------------------+
#property copyright   "TUTTO CORE ENGINE v1.4"
#property version     "1.40"
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
input int    Fractal_Left      = 2;
input int    ATR_Period        = 14;
input double Revalidate_ATRx   = 2.0;
input int    Max_Waves         = 50;
input bool   ShowStateLabels   = true;
input bool   ShowStructuralFib = true;
input bool   ShowDynamicFib    = true;

//+------------------------------------------------------------------+
// ENUM
//+------------------------------------------------------------------+
#define DIR_BUY   1
#define DIR_SELL -1

#define STAGE_S1   0
#define STAGE_S2   1
#define STAGE_S3A  2
#define STAGE_S3B  3
#define STAGE_S4   4

//+------------------------------------------------------------------+
// BUFFERS
//+------------------------------------------------------------------+
double BuyBuf[];
double SellBuf[];

//+------------------------------------------------------------------+
// HANDLES
//+------------------------------------------------------------------+
int hATR = INVALID_HANDLE;

//+------------------------------------------------------------------+
// WAVE STRUCT — v1.4 Wave Vector
//+------------------------------------------------------------------+
struct TuttoWave
  {
   bool     used;
   int      stage;
   int      direction;

   double   fib0;
   datetime fib0_bar_time;
   int      fib0_bar_idx;

   double   structural_fib1;
   datetime structural_fib1_time;
   int      structural_fib1_idx;

   double   dynamic_fib1;
   datetime dynamic_fib1_time;
   int      dynamic_fib1_idx;

   double   s3b_entry_value;
   int      s3b_entry_bar_idx;

   double   hl_candidate;
   int      hl_candidate_idx;
   int      hl_candidate_confirm_idx; // HL確定が確認されたバー

   int      impulse1_done; // 0/1
   int      impulse2_done; // 0/1

   int      wave_id;
  };

TuttoWave g_waves[];
int       g_wave_count   = 0;
int       g_next_wave_id = 1;

string OBJ_PFX = "TUTTO14_";

//+------------------------------------------------------------------+
// TF別パラメータテーブル
//+------------------------------------------------------------------+
int RequiredBars(ENUM_TIMEFRAMES tf)
  {
   if(tf >= PERIOD_H1)  return 2;
   if(tf >= PERIOD_M15) return 3;
   if(tf >= PERIOD_M5)  return 5;
   return 8; // M1以下
  }

double RequiredStrength(ENUM_TIMEFRAMES tf)
  {
   if(tf >= PERIOD_H1)  return 0.3;
   if(tf >= PERIOD_M15) return 0.5;
   if(tf >= PERIOD_M5)  return 0.7;
   return 1.0;
  }

int S3BMaxWait(ENUM_TIMEFRAMES tf)
  {
   return RequiredBars(tf) * 2;
  }

//+------------------------------------------------------------------+
// OnInit
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf, INDICATOR_DATA);
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1,  PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   hATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(hATR == INVALID_HANDLE) return INIT_FAILED;

   ArrayResize(g_waves, Max_Waves);
   for(int i = 0; i < Max_Waves; i++)
      g_waves[i].used = false;
   g_wave_count = 0;

   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO CORE ENGINE v1.4");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
// OnDeinit
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   ObjectsDeleteAll(0, OBJ_PFX);
  }

//+------------------------------------------------------------------+
// UTIL
//+------------------------------------------------------------------+
void SafeDelete(string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

bool IsFractalHigh(const double &high[], int i, int total, int fl)
  {
   if(i - fl < 0 || i + fl >= total) return false;
   for(int k = 1; k <= fl; k++)
     {
      if(high[i-k] >= high[i]) return false;
      if(high[i+k] >= high[i]) return false;
     }
   return true;
  }

bool IsFractalLow(const double &low[], int i, int total, int fl)
  {
   if(i - fl < 0 || i + fl >= total) return false;
   for(int k = 1; k <= fl; k++)
     {
      if(low[i-k] <= low[i]) return false;
      if(low[i+k] <= low[i]) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
// HL_SCORE 計算（v1.4式：duration/depth/accel の正規化平均）
//+------------------------------------------------------------------+
double CalcDurationScore(int held_bars, int required_bars)
  {
   if(required_bars <= 0) return 0.0;
   double v = (double)held_bars / (double)required_bars;
   return MathMin(v, 1.0);
  }

double CalcAccelScore(double cur_close, double hl_candidate,
                      double atr_val, double required_strength)
  {
   if(atr_val <= 0 || required_strength <= 0) return 0.0;
   double v = MathAbs(cur_close - hl_candidate) / (atr_val * required_strength);
   return MathMin(v, 1.0);
  }

double CalcDepthScore(double fib0, double fib1_candidate, double hl_candidate, int direction)
  {
   double impulse_range = MathAbs(fib1_candidate - fib0);
   if(impulse_range <= 0) return 0.0;

   double actual_ratio;
   if(direction == DIR_BUY)
      actual_ratio = (fib1_candidate - hl_candidate) / impulse_range;
   else
      actual_ratio = (hl_candidate - fib1_candidate) / impulse_range;

   double ideal_ratio    = 0.382;
   double ideal_tolerance = 0.236;
   double deviation = MathAbs(actual_ratio - ideal_ratio);

   double score = 1.0 - (deviation / ideal_tolerance);
   return MathMax(0.0, score);
  }

double CalcHLScore(double duration_score, double depth_score, double accel_score)
  {
   return (duration_score + depth_score + accel_score) / 3.0;
  }

//+------------------------------------------------------------------+
// WAVE管理: 空きスロット確保
//+------------------------------------------------------------------+
int AllocWaveSlot()
  {
   for(int i = 0; i < Max_Waves; i++)
     {
      if(!g_waves[i].used)
        {
         g_waves[i].used = true;
         g_waves[i].wave_id = g_next_wave_id++;
         g_waves[i].stage = STAGE_S1;
         g_waves[i].impulse1_done = 0;
         g_waves[i].impulse2_done = 0;
         g_waves[i].s3b_entry_value = 0.0;
         g_waves[i].s3b_entry_bar_idx = -1;
         g_waves[i].hl_candidate = 0.0;
         g_waves[i].hl_candidate_idx = -1;
         g_waves[i].hl_candidate_confirm_idx = -1;
         return i;
        }
     }
   return -1; // 満杯
  }

void KillWave(int idx)
  {
   g_waves[idx].stage = STAGE_S4;
   // 描画オブジェクト削除
   string base = OBJ_PFX + "W" + IntegerToString(g_waves[idx].wave_id) + "_";
   SafeDelete(base + "SFIB");
   SafeDelete(base + "SFIB_L");
   SafeDelete(base + "DFIB");
   SafeDelete(base + "DFIB_L");
   SafeDelete(base + "STATE");
   g_waves[idx].used = false; // スロット解放（次のwaveに再利用）
  }

//+------------------------------------------------------------------+
// STAGE1: 新規Fib0候補探索（Fractalベース）
//+------------------------------------------------------------------+
void TrySpawnWave(const double &high[], const double &low[],
                  int bar_start, int total, int fl, int direction)
  {
   int search_end = bar_start - 1;
   if(search_end - fl < fl) return;

   if(direction == DIR_BUY)
     {
      for(int i = search_end - fl; i >= fl; i--)
        {
         if(!IsFractalLow(low, i, total, fl)) continue;

         // 既存waveが同じFib0付近を保持していれば重複生成しない
         bool dup = false;
         for(int w = 0; w < Max_Waves; w++)
           {
            if(g_waves[w].used && g_waves[w].direction == DIR_BUY &&
               g_waves[w].fib0_bar_idx == i)
              { dup = true; break; }
           }
         if(dup) break;

         int slot = AllocWaveSlot();
         if(slot < 0) return;

         g_waves[slot].direction       = DIR_BUY;
         g_waves[slot].fib0            = low[i];
         g_waves[slot].fib0_bar_idx    = i;
         g_waves[slot].dynamic_fib1       = low[i];
         g_waves[slot].dynamic_fib1_idx   = i;
         g_waves[slot].structural_fib1    = low[i];
         g_waves[slot].structural_fib1_idx = i;
         break;
        }
     }
   else
     {
      for(int i = search_end - fl; i >= fl; i--)
        {
         if(!IsFractalHigh(high, i, total, fl)) continue;

         bool dup = false;
         for(int w = 0; w < Max_Waves; w++)
           {
            if(g_waves[w].used && g_waves[w].direction == DIR_SELL &&
               g_waves[w].fib0_bar_idx == i)
              { dup = true; break; }
           }
         if(dup) break;

         int slot = AllocWaveSlot();
         if(slot < 0) return;

         g_waves[slot].direction       = DIR_SELL;
         g_waves[slot].fib0            = high[i];
         g_waves[slot].fib0_bar_idx    = i;
         g_waves[slot].dynamic_fib1       = high[i];
         g_waves[slot].dynamic_fib1_idx   = i;
         g_waves[slot].structural_fib1    = high[i];
         g_waves[slot].structural_fib1_idx = i;
         break;
        }
     }
  }

//+------------------------------------------------------------------+
// STAGE1→STAGE2: Impulse1(Fib0→HL)検出
//+------------------------------------------------------------------+
void UpdateImpulse1(int w, const double &high[], const double &low[],
                    int bar_start, int total, int fl)
  {
   int search_end = bar_start - 1;
   int dir = g_waves[w].direction;
   int fib0_idx = g_waves[w].fib0_bar_idx;

   if(dir == DIR_BUY)
     {
      for(int i = fib0_idx - fl; i >= fl; i--)
        {
         if(i > search_end) continue;
         if(IsFractalLow(low, i, total, fl) && low[i] > g_waves[w].fib0)
           {
            g_waves[w].hl_candidate     = low[i];
            g_waves[w].hl_candidate_idx = i;
            g_waves[w].impulse1_done    = 1;
            break;
           }
        }
     }
   else
     {
      for(int i = fib0_idx - fl; i >= fl; i--)
        {
         if(i > search_end) continue;
         if(IsFractalHigh(high, i, total, fl) && high[i] < g_waves[w].fib0)
           {
            g_waves[w].hl_candidate     = high[i];
            g_waves[w].hl_candidate_idx = i;
            g_waves[w].impulse1_done    = 1;
            break;
           }
        }
     }
  }

//+------------------------------------------------------------------+
// STAGE2: Impulse2(HL→HH)検出 + STAGE2_condition評価
//+------------------------------------------------------------------+
void UpdateImpulse2AndValidate(int w, const double &high[], const double &low[],
                               const double &close[], const datetime &time[],
                               int bar_start, int total, int fl,
                               double atr_val, ENUM_TIMEFRAMES tf)
  {
   if(g_waves[w].impulse1_done == 0) return;

   int search_end = bar_start - 1;
   int dir         = g_waves[w].direction;
   int hl_idx      = g_waves[w].hl_candidate_idx;

   double hh_val = 0;
   int    hh_idx = -1;

   if(dir == DIR_BUY)
     {
      for(int i = hl_idx - fl; i >= fl; i--)
        {
         if(i > search_end) continue;
         if(IsFractalHigh(high, i, total, fl) && high[i] > g_waves[w].hl_candidate)
           {
            hh_val = high[i];
            hh_idx = i;
            break;
           }
        }
     }
   else
     {
      for(int i = hl_idx - fl; i >= fl; i--)
        {
         if(i > search_end) continue;
         if(IsFractalLow(low, i, total, fl) && low[i] < g_waves[w].hl_candidate)
           {
            hh_val = low[i];
            hh_idx = i;
            break;
           }
        }
     }

   if(hh_idx < 0) return; // Impulse2未確定

   g_waves[w].impulse2_done = 1;

   // ---- HL_SCORE 計算 ----
   int held_bars = (hl_idx - hh_idx); // HL確定後、新HH確定までの経過バー数(古い方向)
   if(held_bars < 0) held_bars = 0;

   int required_bars      = RequiredBars(tf);
   double required_strength = RequiredStrength(tf);

   double duration_score = CalcDurationScore(held_bars, required_bars);
   double accel_score    = CalcAccelScore(close[hh_idx], g_waves[w].hl_candidate,
                                          atr_val, required_strength);
   double depth_score     = CalcDepthScore(g_waves[w].fib0, hh_val,
                                          g_waves[w].hl_candidate, dir);
   double hl_score         = CalcHLScore(duration_score, depth_score, accel_score);

   // ---- Fib0維持チェック ----
   bool fib0_maintained;
   if(dir == DIR_BUY) fib0_maintained = (g_waves[w].hl_candidate >= g_waves[w].fib0);
   else               fib0_maintained = (g_waves[w].hl_candidate <= g_waves[w].fib0);

   // ---- 割れ判定(HL - ATR*0.1) ----
   bool hl_broken = false;
   double buffer = atr_val * 0.1;
   for(int i = hl_idx - 1; i >= hh_idx; i--)
     {
      if(i < 0 || i >= total) continue;
      if(dir == DIR_BUY)
        {
         if(low[i] < g_waves[w].hl_candidate - buffer) { hl_broken = true; break; }
        }
      else
        {
         if(high[i] > g_waves[w].hl_candidate + buffer) { hl_broken = true; break; }
        }
     }

   // ---- STAGE2_condition 評価 ----
   bool stage2_ok = (g_waves[w].impulse1_done == 1) &&
                    (g_waves[w].impulse2_done == 1) &&
                    (hl_score >= 0.6) &&
                    (accel_score >= required_strength) &&
                    fib0_maintained &&
                    (!hl_broken);

   if(stage2_ok)
     {
      // Structural Fib1 LOCK（単調性チェック付き）
      bool monotonic_ok;
      if(dir == DIR_BUY) monotonic_ok = (hh_val > g_waves[w].structural_fib1);
      else               monotonic_ok = (hh_val < g_waves[w].structural_fib1);

      if(g_waves[w].stage == STAGE_S1 || monotonic_ok)
        {
         g_waves[w].structural_fib1     = hh_val;
         g_waves[w].structural_fib1_idx = hh_idx;
         g_waves[w].structural_fib1_time = time[hh_idx];
         g_waves[w].dynamic_fib1         = hh_val;
         g_waves[w].dynamic_fib1_idx     = hh_idx;
         g_waves[w].dynamic_fib1_time    = time[hh_idx];

         if(g_waves[w].stage == STAGE_S3B)
            g_waves[w].stage = STAGE_S3A; // RE-VALIDATION成功
         else
            g_waves[w].stage = STAGE_S3A; // STAGE1/S2初回成立
        }
     }
   else
     {
      // STAGE2不成立: S3B中ならタイムアウト判定はOnCalculate側で実施
      if(g_waves[w].stage == STAGE_S1)
        {
         // 初回認証失敗 → 棄却(枠は維持、再探索継続)
         g_waves[w].impulse1_done = 0;
         g_waves[w].impulse2_done = 0;
        }
     }
  }

//+------------------------------------------------------------------+
// Dynamic Fib1 更新（STAGE3A中のみ、進行ログとして常時更新）
//+------------------------------------------------------------------+
void UpdateDynamicFib1(int w, const double &high[], const double &low[],
                       const datetime &time[], int bar_start, int total, int fl)
  {
   if(g_waves[w].stage != STAGE_S3A) return;
   int dir = g_waves[w].direction;
   int search_end = bar_start - 1;

   if(dir == DIR_BUY)
     {
      for(int i = search_end - fl; i > g_waves[w].dynamic_fib1_idx; i--)
        {
         if(IsFractalHigh(high, i, total, fl) && high[i] > g_waves[w].dynamic_fib1)
           {
            g_waves[w].dynamic_fib1     = high[i];
            g_waves[w].dynamic_fib1_idx = i;
            g_waves[w].dynamic_fib1_time = time[i];
           }
        }
     }
   else
     {
      for(int i = search_end - fl; i > g_waves[w].dynamic_fib1_idx; i--)
        {
         if(IsFractalLow(low, i, total, fl) && low[i] < g_waves[w].dynamic_fib1)
           {
            g_waves[w].dynamic_fib1     = low[i];
            g_waves[w].dynamic_fib1_idx = i;
            g_waves[w].dynamic_fib1_time = time[i];
           }
        }
     }
  }

//+------------------------------------------------------------------+
// STATE TRANSITION EVALUATION（毎確定バーで全wave評価）
//+------------------------------------------------------------------+
void EvaluateWaveTransitions(int w, const double &close[], int bar_idx,
                             double atr_val, ENUM_TIMEFRAMES tf)
  {
   if(!g_waves[w].used) return;
   if(g_waves[w].stage == STAGE_S4) return;

   int dir = g_waves[w].direction;
   double cur_close = close[bar_idx];

   //--- DEATH-1 判定（最優先・全STAGEで評価）
   bool death = false;
   if(g_waves[w].stage == STAGE_S3A)
     {
      if(dir == DIR_BUY)  death = (cur_close < g_waves[w].structural_fib1);
      else                death = (cur_close > g_waves[w].structural_fib1);
     }
   else if(g_waves[w].stage == STAGE_S3B)
     {
      if(dir == DIR_BUY)  death = (cur_close < g_waves[w].s3b_entry_value);
      else                death = (cur_close > g_waves[w].s3b_entry_value);
     }

   if(death)
     {
      KillWave(w);
      return;
     }

   //--- STAGE3A → STAGE3B トリガー
   if(g_waves[w].stage == STAGE_S3A)
     {
      double diff = MathAbs(g_waves[w].dynamic_fib1 - g_waves[w].structural_fib1);
      if(diff >= atr_val * Revalidate_ATRx)
        {
         g_waves[w].stage              = STAGE_S3B;
         g_waves[w].s3b_entry_value    = g_waves[w].structural_fib1;
         g_waves[w].s3b_entry_bar_idx  = bar_idx;
         // 新規STAGE2探索のためimpulseフラグをリセット
         g_waves[w].impulse1_done = 0;
         g_waves[w].impulse2_done = 0;
        }
     }

   //--- STAGE3B タイムアウト判定
   if(g_waves[w].stage == STAGE_S3B)
     {
      int max_wait = S3BMaxWait(tf);
      int elapsed  = g_waves[w].s3b_entry_bar_idx - bar_idx; // 古い方向への経過
      if(elapsed < 0) elapsed = -elapsed;
      if(elapsed >= max_wait && g_waves[w].impulse2_done == 0)
        {
         KillWave(w);
        }
     }
  }

//+------------------------------------------------------------------+
// 描画
//+------------------------------------------------------------------+
void DrawWaveVisuals(int w)
  {
   if(!g_waves[w].used) return;
   string base = OBJ_PFX + "W" + IntegerToString(g_waves[w].wave_id) + "_";

   color dir_clr = (g_waves[w].direction == DIR_BUY) ? clrLime : clrRed;

   if(ShowStructuralFib && (g_waves[w].stage == STAGE_S3A || g_waves[w].stage == STAGE_S3B))
     {
      string name = base + "SFIB";
      SafeDelete(name);
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, g_waves[w].structural_fib1);
      ObjectSetInteger(0, name, OBJPROP_COLOR, dir_clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }

   if(ShowDynamicFib && g_waves[w].stage == STAGE_S3A)
     {
      string name = base + "DFIB";
      SafeDelete(name);
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, g_waves[w].dynamic_fib1);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }

   if(ShowStateLabels)
     {
      string name = base + "STATE";
      SafeDelete(name);
      string stage_txt = "";
      if(g_waves[w].stage == STAGE_S1)  stage_txt = "S1";
      if(g_waves[w].stage == STAGE_S2)  stage_txt = "S2";
      if(g_waves[w].stage == STAGE_S3A) stage_txt = "S3A";
      if(g_waves[w].stage == STAGE_S3B) stage_txt = "S3B";

      if(stage_txt != "" && (g_waves[w].stage == STAGE_S3A || g_waves[w].stage == STAGE_S3B))
        {
         double label_price = g_waves[w].structural_fib1;
         datetime label_time = iTime(_Symbol, PERIOD_CURRENT, 0);
         ObjectCreate(0, name, OBJ_TEXT, 0, label_time, label_price);
         ObjectSetString (0, name, OBJPROP_TEXT, stage_txt);
         ObjectSetInteger(0, name, OBJPROP_COLOR, dir_clr);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
         ObjectSetString (0, name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        }
     }
  }

//+------------------------------------------------------------------+
// OnCalculate
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
   int fl = Fractal_Left;
   int min_req = fl * 10 + ATR_Period + 10;
   if(rates_total < min_req) return 0;

   double atr_buf[];
   ArraySetAsSeries(atr_buf, false);
   if(CopyBuffer(hATR, 0, 0, rates_total, atr_buf) < rates_total) return 0;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;

   int start = (prev_calculated > 1) ? prev_calculated - 1 : min_req;

   for(int i = start; i < rates_total - 1; i++)
     {
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;
      if(i < min_req) continue;

      double atr_val = atr_buf[i];
      if(atr_val <= 0) continue;

      //--- STAGE1: 新規wave探索（BUY/SELL両方向）
      TrySpawnWave(high, low, i, rates_total, fl, DIR_BUY);
      TrySpawnWave(high, low, i, rates_total, fl, DIR_SELL);

      //--- 全waveを処理
      for(int w = 0; w < Max_Waves; w++)
        {
         if(!g_waves[w].used) continue;

         if(g_waves[w].stage == STAGE_S1 || g_waves[w].stage == STAGE_S3B)
           {
            if(g_waves[w].impulse1_done == 0)
               UpdateImpulse1(w, high, low, i, rates_total, fl);

            UpdateImpulse2AndValidate(w, high, low, close, time,
                                      i, rates_total, fl, atr_val, tf);
           }

         UpdateDynamicFib1(w, high, low, time, i, rates_total, fl);

         EvaluateWaveTransitions(w, close, i, atr_val, tf);

         //--- STAGE3A新規移行時に矢印を1回描画
         if(g_waves[w].used && g_waves[w].stage == STAGE_S3A &&
            g_waves[w].structural_fib1_idx == i)
           {
            if(g_waves[w].direction == DIR_BUY)
               BuyBuf[i] = low[i];
            else
               SellBuf[i] = high[i];
           }
        }
     }

   //--- 描画更新（毎確定バーで全waveの可視化を更新）
   for(int w = 0; w < Max_Waves; w++)
      DrawWaveVisuals(w);

   ChartRedraw(0);
   return rates_total;
  }