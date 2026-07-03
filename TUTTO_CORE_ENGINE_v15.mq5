//+------------------------------------------------------------------+
//| TUTTO_CORE_ENGINE_v15.mq5                                       |
//| Layer1(Fact Layer) / Layer2(Interpretation Layer) 完全分離版     |
//|                                                                   |
//| Layer1: 波構造検出のみ。WavePacketのみを出力。認証帯等は行わない |
//| Layer2: WavePacketのみを入力。認証帯(2.33-2.618/3.77-4.236)導出 |
//|         Layer1の内部状態には一切依存しない                      |
//+------------------------------------------------------------------+
#property copyright   "TUTTO CORE ENGINE v1.5"
#property version     "1.50"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   0

input int    Fractal_Left       = 2;
input int    ATR_Period         = 14;
input double Revalidate_ATRx    = 2.0;
input int    Max_Waves          = 20;
input bool   ShowStructuralFib  = true;
input bool   ShowDynamicFib     = true;
input bool   ShowAuthZone       = true;   // Layer2: 認証帯表示
input bool   ShowWaveList       = true;
input double HL_Score_Threshold = 0.6;

#define DIR_BUY    1
#define DIR_SELL  -1
#define STAGE_S1   0
#define STAGE_S3A  2
#define STAGE_S3B  3
#define STAGE_S4   4

double DummyBuf[];

int      hATR        = INVALID_HANDLE;
datetime g_last_bar   = 0;
int      g_next_id    = 1;
string   OBJ_PFX      = "TCE15_";
double   g_atr_last    = 0.0;

//+------------------------------------------------------------------+
// ============== LAYER 1: FACT LAYER ==============
// 波の構造検出のみを担当。認証帯・MA・MGS・採用判定は行わない。
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
// WavePacket — Layer1からLayer2への唯一の受け渡しデータ
// Layer2はこの構造体のフィールドのみを参照する
//+------------------------------------------------------------------+
struct WavePacket
  {
   int      wave_id;
   int      direction;          // DIR_BUY / DIR_SELL
   double   fib0;
   double   structural_fib1;
   int      confirmed_bar_idx;
   datetime confirmed_bar_time;
   double   recorded_accel;     // accメタデータ（記録専用）
   int      wave_stage;         // STAGE_S3A / S3B / S4
  };

//+------------------------------------------------------------------+
// TuttoWave — Layer1内部のみで使用する完全な波状態
// Layer2はこの構造体に直接アクセスしない
//+------------------------------------------------------------------+
struct TuttoWave
  {
   bool     used;
   int      stage;
   int      direction;

   double   fib0;
   int      fib0_idx;

   double   structural_fib1;
   int      structural_fib1_idx;
   int      structural_fib1_confirmed_bar; // DEATH-1有効化判定用

   double   dynamic_fib1;
   int      dynamic_fib1_idx;

   double   s3b_entry_value;
   int      s3b_entry_idx;

   // 探索型Impulse用: 前回探索済み位置（増分探索のため）
   int      impulse1_search_pos;
   int      impulse2_search_pos;

   int      impulse1_done;
   double   hl_candidate;
   int      hl_candidate_idx;
   int      hl_marker_drawn;

   int      impulse2_done;
   double   recorded_accel;     // ②: 判定には使わない記録専用メタデータ

   int      wave_id;

   string   obj_sf;
   string   obj_df;
  };

TuttoWave g_waves[];

int    g_required_bars     = 2;
double g_required_strength = 0.3; // 記録目的のみ残置(判定には使用しない)
int    g_s3b_max_wait       = 4;

void InitTFParams()
  {
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   if(tf >= PERIOD_H1)       { g_required_bars = 2; g_required_strength = 0.3; }
   else if(tf >= PERIOD_M15) { g_required_bars = 3; g_required_strength = 0.5; }
   else if(tf >= PERIOD_M5)  { g_required_bars = 5; g_required_strength = 0.7; }
   else                      { g_required_bars = 8; g_required_strength = 1.0; }
   g_s3b_max_wait = g_required_bars * 2;
  }

void SafeDelete(string name)
  {
   if(name != "" && ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
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
// HL_SCORE（判定にはscoreのみ使用。accは記録専用）
//+------------------------------------------------------------------+
double CalcDurationScore(int held_bars)
  {
   if(g_required_bars <= 0) return 0.0;
   return MathMin((double)held_bars / g_required_bars, 1.0);
  }

double CalcDepthScore(double fib0, double fib1v, double hlv, int dir)
  {
   double rng = MathAbs(fib1v - fib0);
   if(rng <= 0) return 0.0;
   double actual = (dir == DIR_BUY) ? (fib1v - hlv)/rng : (hlv - fib1v)/rng;
   return MathMax(0.0, 1.0 - MathAbs(actual - 0.382)/0.236);
  }

double CalcAccelScore(double close_hh, double hlv, double atr_val)
  {
   if(atr_val <= 0 || g_required_strength <= 0) return 0.0;
   return MathMin(MathAbs(close_hh - hlv)/(atr_val * g_required_strength), 1.0);
  }

//+------------------------------------------------------------------+
// WAVE管理
//+------------------------------------------------------------------+
int AllocWave(int dir, double fib0v, int fib0i)
  {
   for(int i = 0; i < Max_Waves; i++)
     {
      if(g_waves[i].used) continue;
      g_waves[i].used                          = true;
      g_waves[i].stage                         = STAGE_S1;
      g_waves[i].direction                     = dir;
      g_waves[i].fib0                          = fib0v;
      g_waves[i].fib0_idx                      = fib0i;
      g_waves[i].structural_fib1               = fib0v;
      g_waves[i].structural_fib1_idx           = fib0i;
      g_waves[i].structural_fib1_confirmed_bar = fib0i;
      g_waves[i].dynamic_fib1                  = fib0v;
      g_waves[i].dynamic_fib1_idx              = fib0i;
      g_waves[i].s3b_entry_value               = 0.0;
      g_waves[i].s3b_entry_idx                 = -1;
      g_waves[i].impulse1_search_pos           = fib0i;
      g_waves[i].impulse2_search_pos           = fib0i;
      g_waves[i].impulse1_done                 = 0;
      g_waves[i].hl_candidate                  = 0.0;
      g_waves[i].hl_candidate_idx              = -1;
      g_waves[i].hl_marker_drawn               = 0;
      g_waves[i].impulse2_done                 = 0;
      g_waves[i].recorded_accel                = 0.0;
      g_waves[i].wave_id                       = g_next_id++;
      string b = OBJ_PFX + "W" + IntegerToString(g_waves[i].wave_id) + "_";
      g_waves[i].obj_sf = b + "SF";
      g_waves[i].obj_df = b + "DF";
      return i;
     }
   return -1;
  }

void KillWave(int w, datetime death_time, double death_price)
  {
   string n = OBJ_PFX + "DEATH_" + IntegerToString(g_waves[w].wave_id);
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_ARROW, 0, death_time, death_price);
      ObjectSetInteger(0, n, OBJPROP_ARROWCODE, 251); // ×
      ObjectSetInteger(0, n, OBJPROP_COLOR,     clrRed);
      ObjectSetInteger(0, n, OBJPROP_WIDTH,     3);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR,
                       (g_waves[w].direction==DIR_BUY)?ANCHOR_TOP:ANCHOR_BOTTOM);
      ObjectSetInteger(0, n, OBJPROP_BACK,      false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,false);
     }
   SafeDelete(g_waves[w].obj_sf);
   SafeDelete(g_waves[w].obj_df);
   g_waves[w].used  = false;
   g_waves[w].stage = STAGE_S4;
  }

//+------------------------------------------------------------------+
// STAGE1: Fib0生成（灰色▲）
//+------------------------------------------------------------------+
void TrySpawnWaves(const double &high[], const double &low[],
                   const datetime &time[], int bar_idx, int total, int fl)
  {
   int check = bar_idx - fl;
   if(check < fl) return;

   if(IsFractalLow(low, check, total, fl))
     {
      bool dup = false;
      for(int w = 0; w < Max_Waves; w++)
         if(g_waves[w].used && g_waves[w].direction == DIR_BUY &&
            g_waves[w].fib0_idx == check) { dup = true; break; }
      if(!dup)
        {
         int slot = AllocWave(DIR_BUY, low[check], check);
         if(slot >= 0)
           {
            string n = OBJ_PFX + "S1_" + IntegerToString(g_waves[slot].wave_id);
            if(ObjectFind(0,n)<0)
              {
               ObjectCreate(0, n, OBJ_ARROW, 0, time[check], low[check]);
               ObjectSetInteger(0,n,OBJPROP_ARROWCODE,233);
               ObjectSetInteger(0,n,OBJPROP_COLOR,clrGray);
               ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
               ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_TOP);
               ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
              }
           }
        }
     }

   if(IsFractalHigh(high, check, total, fl))
     {
      bool dup = false;
      for(int w = 0; w < Max_Waves; w++)
         if(g_waves[w].used && g_waves[w].direction == DIR_SELL &&
            g_waves[w].fib0_idx == check) { dup = true; break; }
      if(!dup)
        {
         int slot = AllocWave(DIR_SELL, high[check], check);
         if(slot >= 0)
           {
            string n = OBJ_PFX + "S1_" + IntegerToString(g_waves[slot].wave_id);
            if(ObjectFind(0,n)<0)
              {
               ObjectCreate(0, n, OBJ_ARROW, 0, time[check], high[check]);
               ObjectSetInteger(0,n,OBJPROP_ARROWCODE,234);
               ObjectSetInteger(0,n,OBJPROP_COLOR,clrGray);
               ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
               ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_BOTTOM);
               ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
// Impulse1: 探索型（増分探索）— ①の修正
// search_posの次から現在確定済みバーまでを走査する
// 「何本後」という時間制約は設けない（関係性のみで判定）
//+------------------------------------------------------------------+
void UpdateImpulse1(int w, const double &high[], const double &low[],
                    const datetime &time[], int bar_idx, int total, int fl)
  {
   if(g_waves[w].impulse1_done) return;

   int scan_to = bar_idx - fl; // Fractal確定にはfl本の後続が必要
   if(scan_to <= g_waves[w].impulse1_search_pos) return;

   int dir = g_waves[w].direction;
   int found_idx = -1;
   double found_val = 0;

   // 増分探索: 前回検査済みの次から、今回確定した範囲まで
   for(int i = g_waves[w].impulse1_search_pos + 1; i <= scan_to; i++)
     {
      if(i <= g_waves[w].fib0_idx) continue;
      if(dir == DIR_BUY)
        {
         if(IsFractalLow(low, i, total, fl) && low[i] > g_waves[w].fib0)
           { found_idx = i; found_val = low[i]; break; }
        }
      else
        {
         if(IsFractalHigh(high, i, total, fl) && high[i] < g_waves[w].fib0)
           { found_idx = i; found_val = high[i]; break; }
        }
     }

   g_waves[w].impulse1_search_pos = scan_to;

   if(found_idx >= 0)
     {
      g_waves[w].hl_candidate     = found_val;
      g_waves[w].hl_candidate_idx = found_idx;
      g_waves[w].impulse2_search_pos = found_idx; // Impulse2探索の起点を更新
      g_waves[w].impulse1_done    = 1;

      if(!g_waves[w].hl_marker_drawn)
        {
         string n = OBJ_PFX + "HL_" + IntegerToString(g_waves[w].wave_id);
         if(ObjectFind(0,n)<0)
           {
            ObjectCreate(0, n, OBJ_ARROW, 0, time[found_idx], found_val);
            ObjectSetInteger(0,n,OBJPROP_ARROWCODE, dir==DIR_BUY?233:234);
            ObjectSetInteger(0,n,OBJPROP_COLOR,clrYellow);
            ObjectSetInteger(0,n,OBJPROP_WIDTH,2);
            ObjectSetInteger(0,n,OBJPROP_ANCHOR, dir==DIR_BUY?ANCHOR_TOP:ANCHOR_BOTTOM);
            ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
           }
         g_waves[w].hl_marker_drawn = 1;
        }
     }
  }

//+------------------------------------------------------------------+
// Impulse2: 探索型（増分探索）— ①の修正
// stage2_ok判定はscoreのみ。accは記録専用（②の修正）
//+------------------------------------------------------------------+
bool UpdateImpulse2(int w, const double &high[], const double &low[],
                    const double &close[], const datetime &time[],
                    int bar_idx, int total, int fl, double atr_val)
  {
   if(!g_waves[w].impulse1_done) return false;

   int scan_to = bar_idx - fl;
   if(scan_to <= g_waves[w].impulse2_search_pos) return false;

   int dir = g_waves[w].direction;
   int found_idx = -1;
   double found_val = 0;

   for(int i = g_waves[w].impulse2_search_pos + 1; i <= scan_to; i++)
     {
      if(i <= g_waves[w].hl_candidate_idx) continue;
      if(dir == DIR_BUY)
        {
         if(IsFractalHigh(high, i, total, fl) && high[i] > g_waves[w].hl_candidate)
           { found_idx = i; found_val = high[i]; break; }
        }
      else
        {
         if(IsFractalLow(low, i, total, fl) && low[i] < g_waves[w].hl_candidate)
           { found_idx = i; found_val = low[i]; break; }
        }
     }

   g_waves[w].impulse2_search_pos = scan_to;

   if(found_idx < 0) return false;

   int    hh_idx = found_idx;
   double hh_val = found_val;

   int    held = hh_idx - g_waves[w].hl_candidate_idx;
   double dur  = CalcDurationScore(held);
   double dep  = CalcDepthScore(g_waves[w].fib0, hh_val, g_waves[w].hl_candidate, dir);
   double acc  = CalcAccelScore(close[hh_idx], g_waves[w].hl_candidate, atr_val);
   double score = (dur + dep + acc) / 3.0;

   bool fib0_ok = (dir == DIR_BUY)
                  ? (g_waves[w].hl_candidate >= g_waves[w].fib0)
                  : (g_waves[w].hl_candidate <= g_waves[w].fib0);

   bool hl_broken = false;
   double buf = atr_val * 0.1;
   for(int i = g_waves[w].hl_candidate_idx; i <= hh_idx && i < total; i++)
     {
      if(dir == DIR_BUY  && low[i]  < g_waves[w].hl_candidate - buf) { hl_broken = true; break; }
      if(dir == DIR_SELL && high[i] > g_waves[w].hl_candidate + buf) { hl_broken = true; break; }
     }

   // ②: stage2_okはscoreのみで判定。acc単独ゲートは削除済み
   bool stage2_ok = fib0_ok && !hl_broken && (score >= HL_Score_Threshold);

   g_waves[w].recorded_accel = acc; // accは記録専用メタデータとして保持

   if(stage2_ok)
     {
      bool mono = (dir == DIR_BUY)
                  ? (hh_val > g_waves[w].structural_fib1)
                  : (hh_val < g_waves[w].structural_fib1);

      if(g_waves[w].stage == STAGE_S1 || g_waves[w].stage == STAGE_S3B || mono)
        {
         g_waves[w].structural_fib1               = hh_val;
         g_waves[w].structural_fib1_idx            = hh_idx;
         g_waves[w].structural_fib1_confirmed_bar  = hh_idx; // ③で使用
         g_waves[w].dynamic_fib1                   = hh_val;
         g_waves[w].dynamic_fib1_idx                = hh_idx;
         g_waves[w].impulse2_done                   = 1;
         g_waves[w].stage                           = STAGE_S3A;

         string n = OBJ_PFX + "S3A_" + IntegerToString(g_waves[w].wave_id)
                    + "_" + IntegerToString(hh_idx);
         if(ObjectFind(0,n)<0)
           {
            ObjectCreate(0, n, OBJ_ARROW, 0, time[hh_idx], hh_val);
            ObjectSetInteger(0,n,OBJPROP_ARROWCODE, dir==DIR_BUY?233:234);
            ObjectSetInteger(0,n,OBJPROP_COLOR,clrLime);
            ObjectSetInteger(0,n,OBJPROP_WIDTH,3);
            ObjectSetInteger(0,n,OBJPROP_ANCHOR, dir==DIR_BUY?ANCHOR_TOP:ANCHOR_BOTTOM);
            ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
           }
         return true;
        }
     }
   else
     {
      if(g_waves[w].stage != STAGE_S3B)
        {
         g_waves[w].impulse1_done   = 0;
         g_waves[w].impulse2_done   = 0;
         g_waves[w].hl_marker_drawn = 0;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
// Dynamic Fib1更新（探索型・増分方式に統一）
//+------------------------------------------------------------------+
void UpdateDynamicFib1(int w, const double &high[], const double &low[],
                       int bar_idx, int total, int fl)
  {
   if(g_waves[w].stage != STAGE_S3A) return;

   int scan_to = bar_idx - fl;
   if(scan_to <= g_waves[w].dynamic_fib1_idx) return;

   int dir = g_waves[w].direction;
   for(int i = g_waves[w].dynamic_fib1_idx + 1; i <= scan_to; i++)
     {
      if(dir == DIR_BUY)
        {
         if(IsFractalHigh(high, i, total, fl) && high[i] > g_waves[w].dynamic_fib1)
           { g_waves[w].dynamic_fib1 = high[i]; g_waves[w].dynamic_fib1_idx = i; }
        }
      else
        {
         if(IsFractalLow(low, i, total, fl) && low[i] < g_waves[w].dynamic_fib1)
           { g_waves[w].dynamic_fib1 = low[i]; g_waves[w].dynamic_fib1_idx = i; }
        }
     }
  }

//+------------------------------------------------------------------+
// 状態遷移（DEATH-1） — ③の修正
// 判定式自体(close vs structural_fib1)は維持。
// 評価開始は「確定バーの次バーから」に限定する。
//+------------------------------------------------------------------+
void EvaluateTransitions(int w, double cur_close, datetime cur_time,
                         int bar_idx, double atr_val)
  {
   if(!g_waves[w].used) return;
   int dir = g_waves[w].direction;

   //--- ③: DEATH-1は確定バーと同一バーでは評価しない
   // (確定バー自身は除外。次バー以降のみ有効)
   bool death_eligible_bar =
      (bar_idx > g_waves[w].structural_fib1_confirmed_bar);

   bool dead = false;
   if(death_eligible_bar)
     {
      if(g_waves[w].stage == STAGE_S3A)
         dead = (dir == DIR_BUY) ? (cur_close < g_waves[w].structural_fib1)
                                  : (cur_close > g_waves[w].structural_fib1);
      else if(g_waves[w].stage == STAGE_S3B)
         dead = (dir == DIR_BUY) ? (cur_close < g_waves[w].s3b_entry_value)
                                  : (cur_close > g_waves[w].s3b_entry_value);
     }

   if(dead)
     {
      KillWave(w, cur_time, cur_close);
      return;
     }

   if(g_waves[w].stage == STAGE_S3A)
     {
      double diff = MathAbs(g_waves[w].dynamic_fib1 - g_waves[w].structural_fib1);
      if(diff >= atr_val * Revalidate_ATRx)
        {
         g_waves[w].stage           = STAGE_S3B;
         g_waves[w].s3b_entry_value = g_waves[w].structural_fib1;
         g_waves[w].s3b_entry_idx   = bar_idx;
         g_waves[w].impulse1_done   = 0;
         g_waves[w].impulse2_done   = 0;
         g_waves[w].hl_marker_drawn = 0;
         g_waves[w].impulse1_search_pos = g_waves[w].dynamic_fib1_idx;
         g_waves[w].impulse2_search_pos = g_waves[w].dynamic_fib1_idx;

         string n = OBJ_PFX + "S3B_" + IntegerToString(g_waves[w].wave_id)
                    + "_" + IntegerToString(bar_idx);
         if(ObjectFind(0,n)<0)
           {
            ObjectCreate(0, n, OBJ_ARROW, 0, cur_time, cur_close);
            ObjectSetInteger(0,n,OBJPROP_ARROWCODE, dir==DIR_BUY?233:234);
            ObjectSetInteger(0,n,OBJPROP_COLOR,clrDodgerBlue);
            ObjectSetInteger(0,n,OBJPROP_WIDTH,2);
            ObjectSetInteger(0,n,OBJPROP_ANCHOR, dir==DIR_BUY?ANCHOR_TOP:ANCHOR_BOTTOM);
            ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
           }
        }
     }

   if(g_waves[w].stage == STAGE_S3B)
     {
      int elapsed = bar_idx - g_waves[w].s3b_entry_idx;
      if(elapsed >= g_s3b_max_wait && !g_waves[w].impulse2_done)
         KillWave(w, cur_time, cur_close);
     }
  }

//+------------------------------------------------------------------+
// Layer1 → Layer2 出力: WavePacket生成
// Layer2はこの関数の戻り値のみを参照する
//+------------------------------------------------------------------+
WavePacket BuildWavePacket(int w)
  {
   WavePacket p;
   p.wave_id            = g_waves[w].wave_id;
   p.direction           = g_waves[w].direction;
   p.fib0                = g_waves[w].fib0;
   p.structural_fib1     = g_waves[w].structural_fib1;
   p.confirmed_bar_idx   = g_waves[w].structural_fib1_confirmed_bar;
   p.recorded_accel      = g_waves[w].recorded_accel;
   p.wave_stage          = g_waves[w].stage;
   return p;
  }

//+------------------------------------------------------------------+
// Fib1ライン描画（Layer1の観測結果の可視化）
//+------------------------------------------------------------------+
void DrawFibLines(int w)
  {
   if(!g_waves[w].used) return;
   int dir   = g_waves[w].direction;
   color clr = (dir == DIR_BUY) ? clrLime : clrOrangeRed;

   if(ShowStructuralFib &&
      (g_waves[w].stage == STAGE_S3A || g_waves[w].stage == STAGE_S3B))
     {
      string n = g_waves[w].obj_sf;
      if(ObjectFind(0, n) < 0)
        {
         ObjectCreate(0, n, OBJ_HLINE, 0, 0, g_waves[w].structural_fib1);
         ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, n, OBJPROP_STYLE,
                          g_waves[w].stage==STAGE_S3B?STYLE_DOT:STYLE_SOLID);
         ObjectSetInteger(0, n, OBJPROP_BACK, false);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
        }
      else
        {
         ObjectSetDouble (0, n, OBJPROP_PRICE, g_waves[w].structural_fib1);
         ObjectSetInteger(0, n, OBJPROP_STYLE,
                          g_waves[w].stage==STAGE_S3B?STYLE_DOT:STYLE_SOLID);
        }
     }
   else SafeDelete(g_waves[w].obj_sf);

   if(ShowDynamicFib && g_waves[w].stage == STAGE_S3A)
     {
      string n = g_waves[w].obj_df;
      if(ObjectFind(0, n) < 0)
        {
         ObjectCreate(0, n, OBJ_HLINE, 0, 0, g_waves[w].dynamic_fib1);
         ObjectSetInteger(0, n, OBJPROP_COLOR, clrDimGray);
         ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, n, OBJPROP_BACK, false);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
        }
      else
         ObjectSetDouble(0, n, OBJPROP_PRICE, g_waves[w].dynamic_fib1);
     }
   else SafeDelete(g_waves[w].obj_df);
  }

//+------------------------------------------------------------------+
// ============== LAYER 2: INTERPRETATION LAYER ==============
// WavePacketのみを入力とする。Layer1の内部構造には一切依存しない。
// 認証帯(2.33-2.618 / 3.77-4.236)をここで導出する。
//+------------------------------------------------------------------+

struct AuthZone
  {
   double init_low;    // 初期認証帯下限 (2.330)
   double init_high;   // 初期認証帯上限 (2.618)
   double term_low;    // 終末認証帯下限 (3.770)
   double term_high;   // 終末認証帯上限 (4.236)
  };

//+------------------------------------------------------------------+
// WavePacketから認証帯を導出（Layer2の核心処理）
// Layer1のデータ構造(TuttoWave)には一切アクセスしない
//+------------------------------------------------------------------+
AuthZone DeriveAuthZone(const WavePacket &p)
  {
   AuthZone z;
   double range = MathAbs(p.structural_fib1 - p.fib0);

   if(p.direction == DIR_BUY)
     {
      z.init_low  = p.fib0 + 2.330 * range;
      z.init_high = p.fib0 + 2.618 * range;
      z.term_low  = p.fib0 + 3.770 * range;
      z.term_high = p.fib0 + 4.236 * range;
     }
   else
     {
      z.init_low  = p.fib0 - 2.618 * range;
      z.init_high = p.fib0 - 2.330 * range;
      z.term_low  = p.fib0 - 4.236 * range;
      z.term_high = p.fib0 - 3.770 * range;
     }
   return z;
  }

//+------------------------------------------------------------------+
// Layer2: 認証帯の描画（WavePacketのみから生成）
//+------------------------------------------------------------------+
void DrawAuthZoneLines(const WavePacket &p, datetime t_left)
  {
   if(!ShowAuthZone) return;
   if(p.wave_stage != STAGE_S3A && p.wave_stage != STAGE_S3B) return;

   AuthZone z = DeriveAuthZone(p);
   string base = OBJ_PFX + "AUTH_W" + IntegerToString(p.wave_id) + "_";
   color clr = (p.direction == DIR_BUY) ? clrAqua : clrPink;

   string n1 = base + "INITLO";
   string n2 = base + "INITHI";
   if(ObjectFind(0,n1)<0)
     {
      ObjectCreate(0,n1,OBJ_HLINE,0,0,z.init_low);
      ObjectSetInteger(0,n1,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,n1,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,n1,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,n1,OBJPROP_SELECTABLE,false);
     }
   else ObjectSetDouble(0,n1,OBJPROP_PRICE,z.init_low);

   if(ObjectFind(0,n2)<0)
     {
      ObjectCreate(0,n2,OBJ_HLINE,0,0,z.init_high);
      ObjectSetInteger(0,n2,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,n2,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,n2,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,n2,OBJPROP_SELECTABLE,false);
     }
   else ObjectSetDouble(0,n2,OBJPROP_PRICE,z.init_high);
  }

void DeleteAuthZoneLines(int wave_id)
  {
   string base = OBJ_PFX + "AUTH_W" + IntegerToString(wave_id) + "_";
   SafeDelete(base + "INITLO");
   SafeDelete(base + "INITHI");
  }

//+------------------------------------------------------------------+
// 右端Wave一覧パネル（Layer1の状態 + Layer2の認証帯情報を表示）
//+------------------------------------------------------------------+
void DrawWaveListPanel()
  {
   string base = OBJ_PFX + "PANEL_";
   if(!ShowWaveList) { ObjectsDeleteAll(0, base); return; }

   string t = base + "TITLE";
   if(ObjectFind(0, t) < 0) ObjectCreate(0, t, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, t, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, t, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, t, OBJPROP_YDISTANCE, 10);
   ObjectSetString (0, t, OBJPROP_TEXT,      "== ACTIVE WAVES (L1+L2) ==");
   ObjectSetInteger(0, t, OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, t, OBJPROP_FONTSIZE,  10);
   ObjectSetString (0, t, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, t, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, t, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);

   for(int i = 0; i < Max_Waves; i++)
      SafeDelete(base + "ROW" + IntegerToString(i));

   int y = 28, row = 0;
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].stage != STAGE_S3A && g_waves[w].stage != STAGE_S3B) continue;

      WavePacket p = BuildWavePacket(w);
      AuthZone z = DeriveAuthZone(p);

      string dir_txt   = (p.direction == DIR_BUY) ? "BUY" : "SELL";
      string stage_txt = (p.wave_stage == STAGE_S3A) ? "S3A" : "S3B";
      color  line_clr  = (p.wave_stage == STAGE_S3A) ? clrLime : clrDodgerBlue;
      if(p.direction == DIR_SELL && p.wave_stage == STAGE_S3A) line_clr = clrOrangeRed;

      string txt = StringFormat("W%d %s %s SF1=%s AUTH[%s-%s]",
                                p.wave_id, dir_txt, stage_txt,
                                DoubleToString(p.structural_fib1,_Digits),
                                DoubleToString(z.init_low,_Digits),
                                DoubleToString(z.init_high,_Digits));

      string rn = base + "ROW" + IntegerToString(row);
      ObjectCreate(0, rn, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, rn, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, rn, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, rn, OBJPROP_YDISTANCE, y);
      ObjectSetString (0, rn, OBJPROP_TEXT,      txt);
      ObjectSetInteger(0, rn, OBJPROP_COLOR,     line_clr);
      ObjectSetInteger(0, rn, OBJPROP_FONTSIZE,  8);
      ObjectSetString (0, rn, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, rn, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, rn, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
      y += 16; row++;
      if(row >= Max_Waves) break;
     }

   if(row == 0)
     {
      string rn = base + "ROW0";
      ObjectCreate(0, rn, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, rn, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, rn, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, rn, OBJPROP_YDISTANCE, y);
      ObjectSetString (0, rn, OBJPROP_TEXT,      "(no active wave)");
      ObjectSetInteger(0, rn, OBJPROP_COLOR,     clrGray);
      ObjectSetInteger(0, rn, OBJPROP_FONTSIZE,  9);
      ObjectSetString (0, rn, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, rn, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, rn, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
     }
  }

void UpdateComment(int rates_total, int prev_calculated)
  {
   int s1=0, s3a=0, s3b=0;
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].stage == STAGE_S1)  s1++;
      if(g_waves[w].stage == STAGE_S3A) s3a++;
      if(g_waves[w].stage == STAGE_S3B) s3b++;
     }
   Comment(
      "TUTTO ENGINE v1.5 (Layer1/Layer2分離)\n",
      "Bars=", rates_total, " prev=", prev_calculated, "\n",
      "ATR=", DoubleToString(g_atr_last, _Digits), "\n",
      "S1=", s1, " S3A=", s3a, " S3B=", s3b, "\n",
      "TotalWaveID=", g_next_id - 1
   );
  }

//+------------------------------------------------------------------+
// OnInit
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, DummyBuf, INDICATOR_CALCULATIONS);

   hATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(hATR == INVALID_HANDLE) return INIT_FAILED;

   ArrayResize(g_waves, Max_Waves);
   for(int i = 0; i < Max_Waves; i++)
     {
      g_waves[i].used = false;
      g_waves[i].obj_sf = "";
      g_waves[i].obj_df = "";
     }

   InitTFParams();
   g_last_bar = 0;
   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO ENGINE v1.5");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   ObjectsDeleteAll(0, OBJ_PFX);
   Comment("");
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
   int min_req = ATR_Period + fl * 8 + 10;

   if(rates_total < min_req)
     {
      Comment("TUTTO v1.5 waiting... (", rates_total, "/", min_req, ")");
      return 0;
     }

   double atr_tmp[1];
   if(CopyBuffer(hATR, 0, 1, 1, atr_tmp) > 0)
      g_atr_last = atr_tmp[0];

   datetime cur_bar_time = time[rates_total - 2];
   bool new_bar = (cur_bar_time != g_last_bar);

   if(!new_bar)
     {
      UpdateComment(rates_total, prev_calculated);
      return prev_calculated;
     }

   g_last_bar = cur_bar_time;

   if(g_atr_last <= 0.0)
     {
      UpdateComment(rates_total, prev_calculated);
      return prev_calculated;
     }

   int start = (prev_calculated > 1) ? prev_calculated - 1 : min_req;

   int need = rates_total - start + fl + 2;
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   int got = CopyBuffer(hATR, 0, 0, need, atr_buf);
   if(got <= 0)
     {
      UpdateComment(rates_total, prev_calculated);
      return prev_calculated;
     }

   //--------------------------------------------------------------
   // LAYER 1 実行: 波構造検出のみ
   //--------------------------------------------------------------
   for(int i = start; i <= rates_total - 2; i++)
     {
      int atr_pos = rates_total - 1 - i;
      if(atr_pos < 0 || atr_pos >= got) continue;
      double atr_val = atr_buf[atr_pos];
      if(atr_val <= 0.0) continue;

      TrySpawnWaves(high, low, time, i, rates_total, fl);

      for(int w = 0; w < Max_Waves; w++)
        {
         if(!g_waves[w].used) continue;
         if(g_waves[w].stage == STAGE_S4) continue;

         if(g_waves[w].stage == STAGE_S1 || g_waves[w].stage == STAGE_S3B)
            UpdateImpulse1(w, high, low, time, i, rates_total, fl);

         if(g_waves[w].impulse1_done)
            UpdateImpulse2(w, high, low, close, time, i, rates_total, fl, atr_val);

         UpdateDynamicFib1(w, high, low, i, rates_total, fl);

         EvaluateTransitions(w, close[i], time[i], i, atr_val);
        }
     }

   //--------------------------------------------------------------
   // LAYER 1 可視化: Fib0/Fib1ライン
   //--------------------------------------------------------------
   for(int w = 0; w < Max_Waves; w++)
      DrawFibLines(w);

   //--------------------------------------------------------------
   // LAYER 2 実行: WavePacketを受け取り認証帯を導出・描画
   // Layer1のg_waves構造体には直接アクセスせず
   // BuildWavePacket()を介してのみデータを取得する
   //--------------------------------------------------------------
   datetime panel_time = time[rates_total - 2];
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used)
        {
         continue;
        }
      WavePacket p = BuildWavePacket(w);
      if(p.wave_stage == STAGE_S3A || p.wave_stage == STAGE_S3B)
         DrawAuthZoneLines(p, panel_time);
     }

   DrawWaveListPanel();

   UpdateComment(rates_total, prev_calculated);
   ChartRedraw(0);
   return rates_total;
  }
