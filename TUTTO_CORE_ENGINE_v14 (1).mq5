//+------------------------------------------------------------------+
//| TUTTO_CORE_ENGINE_v14.mq5                                       |
//| TUTTO CORE ARCHITECTURE v1.4 — Complete State Machine           |
//| v1.4仕様1:1実装 / 配列方向修正版 / デバッグComment内蔵          |
//| 配列: index 0=oldest / rates_total-1=newest                      |
//+------------------------------------------------------------------+
#property copyright   "TUTTO CORE ENGINE v1.4"
#property version     "1.41"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "BUY S3A"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3

#property indicator_label2  "SELL S3A"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3

//+------------------------------------------------------------------+
// INPUT
//+------------------------------------------------------------------+
input int    Fractal_Left      = 2;
input int    ATR_Period        = 14;
input double Revalidate_ATRx   = 2.0;
input int    Max_Waves         = 30;
input bool   ShowStateLabels   = true;
input bool   ShowStructuralFib = true;
input bool   ShowDynamicFib    = true;
input double HL_Score_Threshold = 0.6;

//+------------------------------------------------------------------+
// STAGE / DIRECTION 定数
//+------------------------------------------------------------------+
#define DIR_BUY    1
#define DIR_SELL  -1
#define STAGE_S1   0
#define STAGE_S2   1   // 内部ペンディング（S1確定後、S3A前）
#define STAGE_S3A  2
#define STAGE_S3B  3
#define STAGE_S4   4   // 吸収状態

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
// WAVE STRUCT — v1.4 完全ベクトル
//+------------------------------------------------------------------+
struct TuttoWave
  {
   bool     used;
   int      stage;
   int      direction;         // DIR_BUY or DIR_SELL

   // Fib0 — 絶対固定
   double   fib0;
   int      fib0_idx;          // 配列インデックス(0=oldest)

   // Structural Fib1 — 認証された死亡判定基準（単調更新）
   double   structural_fib1;
   int      structural_fib1_idx;

   // Dynamic Fib1 — 進行ログ（可変・常時更新）
   double   dynamic_fib1;
   int      dynamic_fib1_idx;

   // S3B凍結値 — STAGE3B進入時にstructural_fib1をコピー
   double   s3b_entry_value;
   int      s3b_entry_idx;

   // Impulse検出状態
   int      impulse1_done;     // 0/1: LL→HL確定
   int      impulse2_done;     // 0/1: HL→HH確定

   // HL候補（Impulse1で検出）
   double   hl_candidate;
   int      hl_candidate_idx;

   // 矢印描画済みフラグ（1回だけ）
   int      arrow_drawn;

   // wave識別子
   int      wave_id;
  };

TuttoWave g_waves[];
int       g_next_wave_id = 1;
string    OBJ_PFX = "TCE14_";

//+------------------------------------------------------------------+
// TF別パラメータ
//+------------------------------------------------------------------+
int TFRequiredBars()
  {
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   if(tf >= PERIOD_H1)  return 2;
   if(tf >= PERIOD_M15) return 3;
   if(tf >= PERIOD_M5)  return 5;
   return 8;
  }

double TFRequiredStrength()
  {
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   if(tf >= PERIOD_H1)  return 0.3;
   if(tf >= PERIOD_M15) return 0.5;
   if(tf >= PERIOD_M5)  return 0.7;
   return 1.0;
  }

int TFS3BMaxWait()
  {
   return TFRequiredBars() * 2;
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
   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // ↑
   PlotIndexSetInteger(1, PLOT_ARROW, 234);  // ↓

   hATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(hATR == INVALID_HANDLE)
     {
      Print("ERROR: iATR handle failed");
      return INIT_FAILED;
     }

   ArrayResize(g_waves, Max_Waves);
   ArrayInitialize(BuyBuf,  EMPTY_VALUE);
   ArrayInitialize(SellBuf, EMPTY_VALUE);

   for(int i = 0; i < Max_Waves; i++)
      g_waves[i].used = false;

   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO ENGINE v1.4");
   Print("TUTTO ENGINE v1.4 initialized");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
// OnDeinit
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   ObjectsDeleteAll(0, OBJ_PFX);
   Comment("");
  }

//+------------------------------------------------------------------+
// UTIL
//+------------------------------------------------------------------+
void SafeDelete(string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

// Fractal High: high[i]が前後fl本の最高値か
// 配列: 0=oldest, N-1=newest
// i-fl 〜 i+fl 内で高値確認
bool IsFractalHigh(const double &high[], int i, int total, int fl)
  {
   if(i - fl < 0 || i + fl >= total) return false;
   for(int k = 1; k <= fl; k++)
     {
      if(high[i - k] >= high[i]) return false;
      if(high[i + k] >= high[i]) return false;
     }
   return true;
  }

// Fractal Low: low[i]が前後fl本の最安値か
bool IsFractalLow(const double &low[], int i, int total, int fl)
  {
   if(i - fl < 0 || i + fl >= total) return false;
   for(int k = 1; k <= fl; k++)
     {
      if(low[i - k] <= low[i]) return false;
      if(low[i + k] <= low[i]) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
// HL_SCORE 計算（v1.4完全数式）
//+------------------------------------------------------------------+
// duration_score = min(held_bars / required_bars, 1.0)
double CalcDurationScore(int held_bars)
  {
   int req = TFRequiredBars();
   if(req <= 0) return 0.0;
   return MathMin((double)held_bars / req, 1.0);
  }

// depth_score = max(0, 1 - |actual_retrace - 0.382| / 0.236)
// actual_retrace = (fib1 - hl) / impulse_range   [BUY]
double CalcDepthScore(double fib0, double fib1_val, double hl_val, int dir)
  {
   double impulse_range = MathAbs(fib1_val - fib0);
   if(impulse_range <= 0) return 0.0;
   double actual_ratio;
   if(dir == DIR_BUY)
      actual_ratio = (fib1_val - hl_val) / impulse_range;
   else
      actual_ratio = (hl_val - fib1_val) / impulse_range;
   double dev = MathAbs(actual_ratio - 0.382);
   return MathMax(0.0, 1.0 - dev / 0.236);
  }

// accel_score = min(|close_at_hh - hl| / (ATR * required_strength), 1.0)
double CalcAccelScore(double close_at_hh, double hl_val, double atr_val)
  {
   double rs = TFRequiredStrength();
   if(atr_val <= 0 || rs <= 0) return 0.0;
   return MathMin(MathAbs(close_at_hh - hl_val) / (atr_val * rs), 1.0);
  }

double CalcHLScore(double dur, double dep, double acc)
  {
   return (dur + dep + acc) / 3.0;
  }

//+------------------------------------------------------------------+
// WAVE スロット管理
//+------------------------------------------------------------------+
int AllocWave(int dir, double fib0_val, int fib0_idx)
  {
   for(int i = 0; i < Max_Waves; i++)
     {
      if(!g_waves[i].used)
        {
         g_waves[i].used                = true;
         g_waves[i].stage               = STAGE_S1;
         g_waves[i].direction           = dir;
         g_waves[i].fib0                = fib0_val;
         g_waves[i].fib0_idx            = fib0_idx;
         g_waves[i].structural_fib1     = fib0_val;
         g_waves[i].structural_fib1_idx = fib0_idx;
         g_waves[i].dynamic_fib1        = fib0_val;
         g_waves[i].dynamic_fib1_idx    = fib0_idx;
         g_waves[i].s3b_entry_value     = 0.0;
         g_waves[i].s3b_entry_idx       = -1;
         g_waves[i].impulse1_done       = 0;
         g_waves[i].impulse2_done       = 0;
         g_waves[i].hl_candidate        = 0.0;
         g_waves[i].hl_candidate_idx    = -1;
         g_waves[i].arrow_drawn         = 0;
         g_waves[i].wave_id             = g_next_wave_id++;
         return i;
        }
     }
   return -1;
  }

void KillWave(int w)
  {
   string base = OBJ_PFX + "W" + IntegerToString(g_waves[w].wave_id) + "_";
   SafeDelete(base + "SF");
   SafeDelete(base + "DF");
   SafeDelete(base + "ST");
   g_waves[w].used  = false;
   g_waves[w].stage = STAGE_S4;
  }

//+------------------------------------------------------------------+
// ── STAGE1: Fib0候補生成 ──
// 配列方向: 0=oldest, N=newest
// search_end = bar_start - 1 で確定バーのみ
// Fib0はFractalLow(BUY) or FractalHigh(SELL)の最新確定を1件採用
//+------------------------------------------------------------------+
void TrySpawnWaves(const double &high[], const double &low[],
                   int bar_start, int total, int fl)
  {
   int search_end = bar_start - 1;

   // BUY: Fib0 = 直近FractalLow（最新=インデックス大から探索）
   for(int i = search_end - fl; i >= fl; i--)
     {
      if(!IsFractalLow(low, i, total, fl)) continue;
      // 同じfib0_idxのBUY waveが既に存在するか
      bool dup = false;
      for(int w = 0; w < Max_Waves; w++)
         if(g_waves[w].used && g_waves[w].direction == DIR_BUY &&
            g_waves[w].fib0_idx == i) { dup = true; break; }
      if(!dup)
        {
         int slot = AllocWave(DIR_BUY, low[i], i);
         if(slot >= 0)
            Print("SPAWN BUY wave id=", g_waves[slot].wave_id,
                  " fib0=", low[i], " idx=", i);
        }
      break; // 最新の1件のみ
     }

   // SELL: Fib0 = 直近FractalHigh
   for(int i = search_end - fl; i >= fl; i--)
     {
      if(!IsFractalHigh(high, i, total, fl)) continue;
      bool dup = false;
      for(int w = 0; w < Max_Waves; w++)
         if(g_waves[w].used && g_waves[w].direction == DIR_SELL &&
            g_waves[w].fib0_idx == i) { dup = true; break; }
      if(!dup)
        {
         int slot = AllocWave(DIR_SELL, high[i], i);
         if(slot >= 0)
            Print("SPAWN SELL wave id=", g_waves[slot].wave_id,
                  " fib0=", high[i], " idx=", i);
        }
      break;
     }
  }

//+------------------------------------------------------------------+
// ── Impulse1: Fib0の後（新しい側）でHL候補を探す ──
// BUY: Fib0(idx=A)の後（A+1〜search_end）でFractalLow(low>fib0)を探す
// ★重要: インデックスが大きい方が新しい
//+------------------------------------------------------------------+
void UpdateImpulse1(int w, const double &high[], const double &low[],
                    int bar_start, int total, int fl)
  {
   if(g_waves[w].impulse1_done == 1) return;

   int dir      = g_waves[w].direction;
   int fib0_idx = g_waves[w].fib0_idx;
   int max_idx  = bar_start - 1 - fl; // FractalはFL本先読み必要

   if(max_idx <= fib0_idx) return;

   if(dir == DIR_BUY)
     {
      // Fib0より新しい側(idx > fib0_idx)でFractalLowを探す
      // 最新の1件（最大インデックス）を採用
      double best_low = 0;
      int    best_idx = -1;
      for(int i = fib0_idx + 1; i <= max_idx; i++)
        {
         if(!IsFractalLow(low, i, total, fl)) continue;
         if(low[i] <= g_waves[w].fib0) continue; // Fib0より高い安値のみ
         // 最新を優先（インデックスが大きいほど新しい）
         if(i > best_idx) { best_idx = i; best_low = low[i]; }
        }
      if(best_idx > 0)
        {
         g_waves[w].hl_candidate     = best_low;
         g_waves[w].hl_candidate_idx = best_idx;
         g_waves[w].impulse1_done    = 1;
        }
     }
   else // SELL: Fib0より新しい側でFractalHigh(high<fib0)を探す
     {
      double best_high = DBL_MAX;
      int    best_idx  = -1;
      for(int i = fib0_idx + 1; i <= max_idx; i++)
        {
         if(!IsFractalHigh(high, i, total, fl)) continue;
         if(high[i] >= g_waves[w].fib0) continue;
         if(i > best_idx) { best_idx = i; best_high = high[i]; }
        }
      if(best_idx > 0)
        {
         g_waves[w].hl_candidate     = best_high;
         g_waves[w].hl_candidate_idx = best_idx;
         g_waves[w].impulse1_done    = 1;
        }
     }
  }

//+------------------------------------------------------------------+
// ── Impulse2: HL候補の後（さらに新しい側）でHH候補を探す ──
// BUY: hl_idx+1 〜 search_end でFractalHigh(high > hl)を探す
//+------------------------------------------------------------------+
bool UpdateImpulse2(int w, const double &high[], const double &low[],
                    const double &close[], int bar_start, int total,
                    int fl, double atr_val)
  {
   if(g_waves[w].impulse1_done == 0) return false;

   int dir    = g_waves[w].direction;
   int hl_idx = g_waves[w].hl_candidate_idx;
   int max_idx = bar_start - 1 - fl;

   if(max_idx <= hl_idx) return false;

   double hh_val = 0;
   int    hh_idx = -1;

   if(dir == DIR_BUY)
     {
      for(int i = hl_idx + 1; i <= max_idx; i++)
        {
         if(!IsFractalHigh(high, i, total, fl)) continue;
         if(high[i] <= g_waves[w].hl_candidate) continue;
         if(i > hh_idx) { hh_idx = i; hh_val = high[i]; }
        }
     }
   else
     {
      for(int i = hl_idx + 1; i <= max_idx; i++)
        {
         if(!IsFractalLow(low, i, total, fl)) continue;
         if(low[i] >= g_waves[w].hl_candidate) continue;
         if(i > hh_idx) { hh_idx = i; hh_val = low[i]; }
        }
     }

   if(hh_idx < 0) return false;

   //--- HL_SCORE計算
   // held_bars: hlからhhまでの経過バー数
   int held_bars = hh_idx - hl_idx;
   double close_at_hh = close[hh_idx];

   double dur = CalcDurationScore(held_bars);
   double dep = CalcDepthScore(g_waves[w].fib0, hh_val,
                               g_waves[w].hl_candidate, dir);
   double acc = CalcAccelScore(close_at_hh, g_waves[w].hl_candidate, atr_val);
   double hl_score = CalcHLScore(dur, dep, acc);

   //--- Fib0維持チェック
   bool fib0_ok;
   if(dir == DIR_BUY) fib0_ok = (g_waves[w].hl_candidate >= g_waves[w].fib0);
   else               fib0_ok = (g_waves[w].hl_candidate <= g_waves[w].fib0);

   //--- HL割れ判定: HL〜HHの間でHL-ATR*0.1を割ったか
   bool hl_broken = false;
   double buf = atr_val * 0.1;
   for(int i = hl_idx; i <= hh_idx; i++)
     {
      if(i < 0 || i >= total) continue;
      if(dir == DIR_BUY && low[i] < g_waves[w].hl_candidate - buf)
        { hl_broken = true; break; }
      if(dir == DIR_SELL && high[i] > g_waves[w].hl_candidate + buf)
        { hl_broken = true; break; }
     }

   //--- STAGE2成立判定
   double rs = TFRequiredStrength();
   bool stage2_ok = fib0_ok && !hl_broken &&
                    (hl_score >= HL_Score_Threshold) &&
                    (acc >= rs);

   if(stage2_ok)
     {
      // 単調性チェック: Structural Fib1の更新方向確認
      bool mono_ok;
      if(dir == DIR_BUY) mono_ok = (hh_val > g_waves[w].structural_fib1);
      else               mono_ok = (hh_val < g_waves[w].structural_fib1);

      if(g_waves[w].stage == STAGE_S1 || g_waves[w].stage == STAGE_S2 || mono_ok)
        {
         g_waves[w].structural_fib1     = hh_val;
         g_waves[w].structural_fib1_idx = hh_idx;
         g_waves[w].dynamic_fib1        = hh_val;
         g_waves[w].dynamic_fib1_idx    = hh_idx;
         g_waves[w].impulse2_done       = 1;

         if(g_waves[w].stage == STAGE_S3B)
           {
            // RE-VALIDATION成功
            g_waves[w].stage = STAGE_S3A;
            Print("Wave", g_waves[w].wave_id,
                  " S3B→S3A success, new SF1=", hh_val);
           }
         else
           {
            // 初回STAGE2成立
            g_waves[w].stage = STAGE_S3A;
            Print("Wave", g_waves[w].wave_id,
                  " STAGE2→S3A locked, SF1=", hh_val,
                  " HL_SCORE=", hl_score);
           }
         return true;
        }
     }
   else
     {
      // STAGE2不成立 → impulseリセットして再探索
      if(g_waves[w].stage != STAGE_S3B)
        {
         g_waves[w].impulse1_done = 0;
         g_waves[w].impulse2_done = 0;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
// ── Dynamic Fib1更新 (STAGE3Aのみ) ──
// BUY: S3A中にFractalHighが更新されれば動的追跡
//+------------------------------------------------------------------+
void UpdateDynamicFib1(int w, const double &high[], const double &low[],
                       int bar_start, int total, int fl)
  {
   if(g_waves[w].stage != STAGE_S3A) return;

   int dir     = g_waves[w].direction;
   int max_idx = bar_start - 1 - fl;
   int cur_idx = g_waves[w].dynamic_fib1_idx;

   if(max_idx <= cur_idx) return;

   if(dir == DIR_BUY)
     {
      for(int i = cur_idx + 1; i <= max_idx; i++)
        {
         if(IsFractalHigh(high, i, total, fl) && high[i] > g_waves[w].dynamic_fib1)
           {
            g_waves[w].dynamic_fib1     = high[i];
            g_waves[w].dynamic_fib1_idx = i;
           }
        }
     }
   else
     {
      for(int i = cur_idx + 1; i <= max_idx; i++)
        {
         if(IsFractalLow(low, i, total, fl) && low[i] < g_waves[w].dynamic_fib1)
           {
            g_waves[w].dynamic_fib1     = low[i];
            g_waves[w].dynamic_fib1_idx = i;
           }
        }
     }
  }

//+------------------------------------------------------------------+
// ── 状態遷移評価 ──
// DEATH-1が最優先（全STAGEで評価）
//+------------------------------------------------------------------+
void EvaluateTransitions(int w, const double &close[],
                         int bar_idx, double atr_val)
  {
   if(!g_waves[w].used) return;
   int dir = g_waves[w].direction;
   double cur = close[bar_idx];

   //--- DEATH-1: 最優先
   bool dead = false;
   if(g_waves[w].stage == STAGE_S3A)
     {
      if(dir == DIR_BUY)  dead = (cur < g_waves[w].structural_fib1);
      else                dead = (cur > g_waves[w].structural_fib1);
     }
   else if(g_waves[w].stage == STAGE_S3B)
     {
      if(dir == DIR_BUY)  dead = (cur < g_waves[w].s3b_entry_value);
      else                dead = (cur > g_waves[w].s3b_entry_value);
     }

   if(dead)
     {
      Print("Wave", g_waves[w].wave_id, " DEATH at bar=", bar_idx);
      KillWave(w);
      return;
     }

   //--- S3A → S3B トリガー
   if(g_waves[w].stage == STAGE_S3A)
     {
      double diff = MathAbs(g_waves[w].dynamic_fib1 - g_waves[w].structural_fib1);
      if(diff >= atr_val * Revalidate_ATRx)
        {
         g_waves[w].stage           = STAGE_S3B;
         g_waves[w].s3b_entry_value = g_waves[w].structural_fib1; // SF1を凍結
         g_waves[w].s3b_entry_idx   = bar_idx;
         // S3B中はimpulseを再探索
         g_waves[w].impulse1_done   = 0;
         g_waves[w].impulse2_done   = 0;
         Print("Wave", g_waves[w].wave_id, " S3A→S3B triggered at bar=", bar_idx);
        }
     }

   //--- S3B タイムアウト → STAGE4
   if(g_waves[w].stage == STAGE_S3B)
     {
      int elapsed = bar_idx - g_waves[w].s3b_entry_idx;
      if(elapsed >= TFS3BMaxWait() && g_waves[w].impulse2_done == 0)
        {
         Print("Wave", g_waves[w].wave_id, " S3B timeout → DEATH");
         KillWave(w);
        }
     }
  }

//+------------------------------------------------------------------+
// ── 描画 ──
//+------------------------------------------------------------------+
void DrawWave(int w, const double &high[], const double &low[],
              const datetime &time[], int bar_cur)
  {
   if(!g_waves[w].used) return;
   string base = OBJ_PFX + "W" + IntegerToString(g_waves[w].wave_id) + "_";
   int dir = g_waves[w].direction;
   color c_dir = (dir == DIR_BUY) ? clrLime : clrOrangeRed;

   // Structural Fib1 水平線
   if(ShowStructuralFib &&
      (g_waves[w].stage == STAGE_S3A || g_waves[w].stage == STAGE_S3B))
     {
      string n = base + "SF";
      SafeDelete(n);
      if(ObjectCreate(0, n, OBJ_HLINE, 0, 0, g_waves[w].structural_fib1))
        {
         ObjectSetInteger(0, n, OBJPROP_COLOR, c_dir);
         ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, n, OBJPROP_STYLE,
                          g_waves[w].stage == STAGE_S3B ? STYLE_DOT : STYLE_SOLID);
         ObjectSetInteger(0, n, OBJPROP_BACK, false);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
        }
     }

   // Dynamic Fib1 水平線
   if(ShowDynamicFib && g_waves[w].stage == STAGE_S3A)
     {
      string n = base + "DF";
      SafeDelete(n);
      if(ObjectCreate(0, n, OBJ_HLINE, 0, 0, g_waves[w].dynamic_fib1))
        {
         ObjectSetInteger(0, n, OBJPROP_COLOR, clrDimGray);
         ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, n, OBJPROP_BACK, false);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
        }
     }

   // ステートラベル
   if(ShowStateLabels &&
      (g_waves[w].stage == STAGE_S3A || g_waves[w].stage == STAGE_S3B))
     {
      string n = base + "ST";
      SafeDelete(n);
      string txt = (g_waves[w].stage == STAGE_S3A) ? "S3A" : "S3B";
      txt = txt + " W" + IntegerToString(g_waves[w].wave_id);
      int label_idx = bar_cur;
      if(label_idx >= 0 && label_idx < ArraySize(time))
        {
         double label_price = (dir == DIR_BUY)
                              ? g_waves[w].structural_fib1
                              : g_waves[w].structural_fib1;
         if(ObjectCreate(0, n, OBJ_TEXT, 0, time[label_idx], label_price))
           {
            ObjectSetString (0, n, OBJPROP_TEXT, txt);
            ObjectSetInteger(0, n, OBJPROP_COLOR, c_dir);
            ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
            ObjectSetString (0, n, OBJPROP_FONT, "Arial Bold");
            ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
            ObjectSetInteger(0, n, OBJPROP_BACK, false);
            ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
           }
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
   int min_req = ATR_Period + fl * 6 + 10;

   if(rates_total < min_req)
     {
      Comment("TUTTO ENGINE v1.4 — WAITING FOR DATA (", rates_total, "/", min_req, ")");
      return 0;
     }

   //--- ATRバッファ取得
   double atr_buf[];
   ArraySetAsSeries(atr_buf, false);
   if(CopyBuffer(hATR, 0, 0, rates_total, atr_buf) < rates_total)
     {
      Comment("TUTTO ENGINE v1.4 — ATR BUFFER ERROR");
      return 0;
     }

   //--- 処理開始バー
   int start = (prev_calculated > 1) ? prev_calculated - 1 : min_req;

   //--- メインループ（確定バーのみ: rates_total-1は未確定のためスキップ）
   for(int i = start; i < rates_total - 1; i++)
     {
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;

      double atr_val = atr_buf[i];
      if(atr_val <= 0.0) continue;

      //--- STAGE1: 新規wave候補生成（毎バー1回）
      TrySpawnWaves(high, low, i, rates_total, fl);

      //--- 全waveを更新
      for(int w = 0; w < Max_Waves; w++)
        {
         if(!g_waves[w].used) continue;
         if(g_waves[w].stage == STAGE_S4) continue;

         //--- Impulse1 探索（S1またはS3B中）
         if(g_waves[w].stage == STAGE_S1 || g_waves[w].stage == STAGE_S3B)
            UpdateImpulse1(w, high, low, i, rates_total, fl);

         //--- Impulse2 探索（impulse1_done==1の場合）
         if(g_waves[w].impulse1_done == 1)
           {
            bool promoted = UpdateImpulse2(w, high, low, close,
                                           i, rates_total, fl, atr_val);
            //--- S3A新規成立 → 矢印を1回描画
            if(promoted && g_waves[w].stage == STAGE_S3A &&
               g_waves[w].arrow_drawn == 0)
              {
               int hh_idx = g_waves[w].structural_fib1_idx;
               if(hh_idx >= 0 && hh_idx < rates_total)
                 {
                  if(g_waves[w].direction == DIR_BUY)
                     BuyBuf[hh_idx] = low[hh_idx];
                  else
                     SellBuf[hh_idx] = high[hh_idx];
                  g_waves[w].arrow_drawn = 1;
                 }
              }
           }

         //--- Dynamic Fib1更新（S3A中）
         UpdateDynamicFib1(w, high, low, i, rates_total, fl);

         //--- 状態遷移評価（DEATH-1最優先）
         EvaluateTransitions(w, close, i, atr_val);
        }
     }

   //--- 描画更新（最終バーで実行）
   int last_confirmed = rates_total - 2;
   if(last_confirmed >= 0)
     {
      for(int w = 0; w < Max_Waves; w++)
         DrawWave(w, high, low, time, last_confirmed);
     }

   //--- デバッグComment: ステージ別件数カウント
   int cnt_s1 = 0, cnt_s2 = 0, cnt_s3a = 0, cnt_s3b = 0, cnt_s4 = 0;
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      switch(g_waves[w].stage)
        {
         case STAGE_S1:  cnt_s1++;  break;
         case STAGE_S2:  cnt_s2++;  break;
         case STAGE_S3A: cnt_s3a++; break;
         case STAGE_S3B: cnt_s3b++; break;
         case STAGE_S4:  cnt_s4++;  break;
        }
     }

   Comment(
      "== TUTTO ENGINE v1.4 ==\n",
      "rates_total = ", rates_total, "\n",
      "prev_calculated = ", prev_calculated, "\n",
      "ATR[last] = ", DoubleToString(atr_buf[rates_total-2], _Digits), "\n",
      "---\n",
      "S1(Hypothesis)  : ", cnt_s1,  "\n",
      "S2(Validation)  : ", cnt_s2,  "\n",
      "S3A(Stable)     : ", cnt_s3a, "\n",
      "S3B(Revalidate) : ", cnt_s3b, "\n",
      "S4(Dead/freed)  : ", cnt_s4,  "\n",
      "Total waves     : ", cnt_s1+cnt_s2+cnt_s3a+cnt_s3b, "\n",
      "---\n",
      "next_wave_id    : ", g_next_wave_id, "\n",
      "FL=", fl, " ATR_Period=", ATR_Period
   );

   ChartRedraw(0);
   return rates_total;
  }
