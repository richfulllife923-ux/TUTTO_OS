//+------------------------------------------------------------------+
//| TUTTO_INDICATOR_vFinal.mq5                                      |
//| TUTTO Market Geometry Indicator — Final Stable Build            |
//|                                                                   |
//| Layer1: Wave構造(市場幾何) — ActiveWave完全安定化               |
//| Layer2: RCI(タイミング)                                          |
//| Layer3: MA200(トレンド方向・MTF優先)                            |
//| Layer4: Volume(補助確認)                                         |
//|                                                                   |
//| 親波(S3A)死亡時は子波(直近のS1候補)へ自動フォールバック           |
//| TP/SL/フィボゾーン/状態ラベルを完全可視化                         |
//| 確定済みバーのみ参照。リペイントなし。                            |
//+------------------------------------------------------------------+
#property copyright   "TUTTO INDICATOR vFinal"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   0

//+------------------------------------------------------------------+
// INPUT
//+------------------------------------------------------------------+
input int    Fractal_Left       = 2;       // Fractal確認本数
input int    ATR_Period         = 14;
input double Revalidate_ATRx    = 2.0;     // S3A→S3B トリガー
input int    Max_Waves          = 20;
input double HL_Score_Threshold = 0.6;

input int    MA_Period          = 200;     // Layer3: トレンド方向MA
input ENUM_TIMEFRAMES MA_HigherTF = PERIOD_H4; // Layer3: 上位TF優先参照

input int    RCI_Period         = 9;       // Layer2: タイミングRCI

input bool   UseVolumeFilter    = true;    // Layer4: 補助確認(構造否定はしない)
input double Volume_MinRatio    = 1.1;     // 直近平均比

input bool   ShowStructuralFib  = true;
input bool   ShowDynamicFib     = true;
input bool   ShowAuthZone       = true;
input bool   ShowWaveList       = true;
input bool   ShowTPSL           = true;
input bool   ShowStateLabel     = true;

//+------------------------------------------------------------------+
// 定数
//+------------------------------------------------------------------+
#define DIR_BUY    1
#define DIR_SELL  -1
#define STAGE_S1   0
#define STAGE_S3A  2
#define STAGE_S3B  3
#define STAGE_S4   4

#define MKT_TREND  1
#define MKT_RANGE  0
#define MKT_BREAK -1

double DummyBuf[];

int      hATR        = INVALID_HANDLE;
int      hMA         = INVALID_HANDLE;
int      hMA_Higher  = INVALID_HANDLE;
datetime g_last_bar   = 0;
int      g_next_id    = 1;
string   OBJ_PFX      = "TCEF_";
double   g_atr_last    = 0.0;

//+------------------------------------------------------------------+
// ============== LAYER 1: WAVE STRUCTURE (市場幾何) ==============
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
// WavePacket — Layer1 → Layer2/3/4 への唯一の受け渡しデータ
//+------------------------------------------------------------------+
struct WavePacket
  {
   int      wave_id;
   int      direction;
   double   fib0;
   double   structural_fib1;
   int      confirmed_bar_idx;
   datetime confirmed_bar_time;
   double   recorded_accel;
   int      wave_stage;
   bool     is_fallback;        // 子波フォールバックで生成されたか
  };

// 固定サイズ配列。未使用スロットは wave_id==0 で無効化
WavePacket g_active_packets[];
int        g_active_packet_count = 0;

//+------------------------------------------------------------------+
// TuttoWave — Layer1内部の完全な波状態
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
   int      structural_fib1_confirmed_bar;

   double   dynamic_fib1;
   int      dynamic_fib1_idx;

   double   s3b_entry_value;
   int      s3b_entry_idx;

   int      impulse1_search_pos;
   int      impulse2_search_pos;

   int      impulse1_done;
   double   hl_candidate;
   int      hl_candidate_idx;
   int      hl_marker_drawn;

   int      impulse2_done;
   double   recorded_accel;

   bool     is_parent;          // 親波として登録されたか(最新の主waveか)
   bool     is_fallback;        // 子波からのフォールバックで生成されたか

   int      wave_id;

   string   obj_sf;
   string   obj_df;
   string   obj_tp1;
   string   obj_tp2;
   string   obj_tp3;
   string   obj_sl;
   string   obj_wid;      // Wave番号常時表示用ラベル
  };

TuttoWave g_waves[];

// 直近で死亡したS3A波の情報を保持（子波フォールバック用）
struct LastDeadParent
  {
   bool     valid;
   int      direction;
   double   fib0;
   double   structural_fib1;
   int      death_bar_idx;
  };
LastDeadParent g_last_dead[2]; // [0]=BUY系の最終死亡, [1]=SELL系の最終死亡

int    g_required_bars     = 2;
double g_required_strength = 0.3;
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
// HL_SCORE
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
// WAVE管理（破綻防止: 配列範囲チェック・未初期化排除）
//+------------------------------------------------------------------+
int AllocWave(int dir, double fib0v, int fib0i, bool fallback)
  {
   if(fib0i < 0) return -1; // 安全ガード

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
      g_waves[i].is_parent                     = false;
      g_waves[i].is_fallback                   = fallback;
      g_waves[i].wave_id                       = g_next_id++;
      string b = OBJ_PFX + "W" + IntegerToString(g_waves[i].wave_id) + "_";
      g_waves[i].obj_sf  = b + "SF";
      g_waves[i].obj_df  = b + "DF";
      g_waves[i].obj_tp1 = b + "TP1";
      g_waves[i].obj_tp2 = b + "TP2";
      g_waves[i].obj_tp3 = b + "TP3";
      g_waves[i].obj_sl  = b + "SL";
      g_waves[i].obj_wid = b + "WID";
      return i;
     }
   return -1; // 満杯。破綻させずfalse相当を返す
  }

void DeleteWaveVisuals(int w)
  {
   if(w < 0 || w >= Max_Waves) return; // 安定性: 範囲外アクセス防止
   SafeDelete(g_waves[w].obj_sf);
   SafeDelete(g_waves[w].obj_df);
   SafeDelete(g_waves[w].obj_tp1);
   SafeDelete(g_waves[w].obj_tp2);
   SafeDelete(g_waves[w].obj_tp3);
   SafeDelete(g_waves[w].obj_sl);
   SafeDelete(g_waves[w].obj_wid);
  }

void KillWave(int w, datetime death_time, double death_price)
  {
   if(w < 0 || w >= Max_Waves) return; // 破綻防止ガード
   if(!g_waves[w].used) return;

   string n = OBJ_PFX + "DEATH_" + IntegerToString(g_waves[w].wave_id);
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_ARROW, 0, death_time, death_price);
      ObjectSetInteger(0, n, OBJPROP_ARROWCODE, 251);
      ObjectSetInteger(0, n, OBJPROP_COLOR,     clrRed);
      ObjectSetInteger(0, n, OBJPROP_WIDTH,     3);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR,
                       (g_waves[w].direction==DIR_BUY)?ANCHOR_TOP:ANCHOR_BOTTOM);
      ObjectSetInteger(0, n, OBJPROP_BACK,      false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,false);
     }

   // 親波が死亡した場合は子波フォールバック用の記憶を更新
   if(g_waves[w].is_parent)
     {
      int slot = (g_waves[w].direction == DIR_BUY) ? 0 : 1;
      g_last_dead[slot].valid           = true;
      g_last_dead[slot].direction       = g_waves[w].direction;
      g_last_dead[slot].fib0            = g_waves[w].fib0;
      g_last_dead[slot].structural_fib1 = g_waves[w].structural_fib1;
     }

   DeleteWaveVisuals(w);
   g_waves[w].used  = false;
   g_waves[w].stage = STAGE_S4;
  }

//+------------------------------------------------------------------+
// STAGE1: Fib0生成（灰色▲）+ 親波/子波の自動判別
// 同方向の既存波が無い場合、新規波を「親波」として登録する
//+------------------------------------------------------------------+
void TrySpawnWaves(const double &high[], const double &low[],
                   const datetime &time[], int bar_idx, int total, int fl)
  {
   int check = bar_idx - fl;
   if(check < fl || check >= total) return; // 範囲外アクセス防止

   if(IsFractalLow(low, check, total, fl))
     {
      bool dup = false;
      bool has_parent = false;
      for(int w = 0; w < Max_Waves; w++)
        {
         if(!g_waves[w].used) continue;
         if(g_waves[w].direction == DIR_BUY && g_waves[w].fib0_idx == check)
           { dup = true; break; }
         if(g_waves[w].direction == DIR_BUY && g_waves[w].is_parent)
            has_parent = true;
        }
      if(!dup)
        {
         int slot = AllocWave(DIR_BUY, low[check], check, false);
         if(slot >= 0)
           {
            if(!has_parent) g_waves[slot].is_parent = true; // 最初の波を親に
            string n = OBJ_PFX + "S1_" + IntegerToString(g_waves[slot].wave_id);
            if(ObjectFind(0,n)<0 && check>=0 && check<ArraySize(time))
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
      bool has_parent = false;
      for(int w = 0; w < Max_Waves; w++)
        {
         if(!g_waves[w].used) continue;
         if(g_waves[w].direction == DIR_SELL && g_waves[w].fib0_idx == check)
           { dup = true; break; }
         if(g_waves[w].direction == DIR_SELL && g_waves[w].is_parent)
            has_parent = true;
        }
      if(!dup)
        {
         int slot = AllocWave(DIR_SELL, high[check], check, false);
         if(slot >= 0)
           {
            if(!has_parent) g_waves[slot].is_parent = true;
            string n = OBJ_PFX + "S1_" + IntegerToString(g_waves[slot].wave_id);
            if(ObjectFind(0,n)<0 && check>=0 && check<ArraySize(time))
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
// 親波フォールバック処理:
// 同方向に有効な親波(STAGE_S3A/S3B/S1で is_parent=true)が
// 存在しない場合、待機中の子波(S1)があれば自動的に親波へ格上げする
//+------------------------------------------------------------------+
void EnsureParentWave(int dir)
  {
   bool has_active_parent = false;
   int  best_child = -1;
   int  best_idx   = -1;

   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].direction != dir) continue;
      if(g_waves[w].is_parent &&
         (g_waves[w].stage==STAGE_S1 || g_waves[w].stage==STAGE_S3A || g_waves[w].stage==STAGE_S3B))
        {
         has_active_parent = true;
        }
      // 子波候補: is_parent=falseで、まだ使用中(S1〜S3B)
      if(!g_waves[w].is_parent &&
         (g_waves[w].stage==STAGE_S1 || g_waves[w].stage==STAGE_S3A || g_waves[w].stage==STAGE_S3B))
        {
         if(g_waves[w].fib0_idx > best_idx) // 最新の子波を優先
           {
            best_idx = g_waves[w].fib0_idx;
            best_child = w;
           }
        }
     }

   if(!has_active_parent && best_child >= 0)
     {
      g_waves[best_child].is_parent   = true;
      g_waves[best_child].is_fallback = true; // フォールバックで親に昇格
     }
  }

//+------------------------------------------------------------------+
// Impulse1: 探索型（増分探索）
//+------------------------------------------------------------------+
void UpdateImpulse1(int w, const double &high[], const double &low[],
                    const datetime &time[], int bar_idx, int total, int fl)
  {
   if(w < 0 || w >= Max_Waves) return;
   if(g_waves[w].impulse1_done) return;

   int scan_to = bar_idx - fl;
   if(scan_to <= g_waves[w].impulse1_search_pos) return;
   if(scan_to >= total) scan_to = total - 1;

   int dir = g_waves[w].direction;
   int found_idx = -1;
   double found_val = 0;

   for(int i = g_waves[w].impulse1_search_pos + 1; i <= scan_to; i++)
     {
      if(i <= g_waves[w].fib0_idx || i < 0 || i >= total) continue;
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
      g_waves[w].hl_candidate        = found_val;
      g_waves[w].hl_candidate_idx    = found_idx;
      g_waves[w].impulse2_search_pos = found_idx;
      g_waves[w].impulse1_done       = 1;

      if(!g_waves[w].hl_marker_drawn)
        {
         string n = OBJ_PFX + "HL_" + IntegerToString(g_waves[w].wave_id);
         if(ObjectFind(0,n)<0 && found_idx>=0 && found_idx<ArraySize(time))
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
// Impulse2: 探索型（増分探索）。stage2_okはscoreのみで判定
//+------------------------------------------------------------------+
bool UpdateImpulse2(int w, const double &high[], const double &low[],
                    const double &close[], const datetime &time[],
                    int bar_idx, int total, int fl, double atr_val)
  {
   if(w < 0 || w >= Max_Waves) return false;
   if(!g_waves[w].impulse1_done) return false;

   int scan_to = bar_idx - fl;
   if(scan_to <= g_waves[w].impulse2_search_pos) return false;
   if(scan_to >= total) scan_to = total - 1;

   int dir = g_waves[w].direction;
   int found_idx = -1;
   double found_val = 0;

   for(int i = g_waves[w].impulse2_search_pos + 1; i <= scan_to; i++)
     {
      if(i <= g_waves[w].hl_candidate_idx || i < 0 || i >= total) continue;
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
   if(found_idx >= total || g_waves[w].hl_candidate_idx < 0) return false;

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

   bool stage2_ok = fib0_ok && !hl_broken && (score >= HL_Score_Threshold);
   g_waves[w].recorded_accel = acc;

   if(stage2_ok)
     {
      bool mono = (dir == DIR_BUY)
                  ? (hh_val > g_waves[w].structural_fib1)
                  : (hh_val < g_waves[w].structural_fib1);

      if(g_waves[w].stage == STAGE_S1 || g_waves[w].stage == STAGE_S3B || mono)
        {
         g_waves[w].structural_fib1               = hh_val;
         g_waves[w].structural_fib1_idx            = hh_idx;
         g_waves[w].structural_fib1_confirmed_bar  = hh_idx;
         g_waves[w].dynamic_fib1                   = hh_val;
         g_waves[w].dynamic_fib1_idx                = hh_idx;
         g_waves[w].impulse2_done                   = 1;
         g_waves[w].stage                           = STAGE_S3A;

         string n = OBJ_PFX + "S3A_" + IntegerToString(g_waves[w].wave_id)
                    + "_" + IntegerToString(hh_idx);
         if(ObjectFind(0,n)<0 && hh_idx>=0 && hh_idx<ArraySize(time))
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
// Dynamic Fib1更新
//+------------------------------------------------------------------+
void UpdateDynamicFib1(int w, const double &high[], const double &low[],
                       int bar_idx, int total, int fl)
  {
   if(w < 0 || w >= Max_Waves) return;
   if(g_waves[w].stage != STAGE_S3A) return;

   int scan_to = bar_idx - fl;
   if(scan_to <= g_waves[w].dynamic_fib1_idx) return;
   if(scan_to >= total) scan_to = total - 1;

   int dir = g_waves[w].direction;
   for(int i = g_waves[w].dynamic_fib1_idx + 1; i <= scan_to; i++)
     {
      if(i < 0 || i >= total) continue;
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
// 状態遷移（DEATH-1）— 確定バー次バー以降で評価
//+------------------------------------------------------------------+
void EvaluateTransitions(int w, double cur_close, datetime cur_time,
                         int bar_idx, double atr_val)
  {
   if(w < 0 || w >= Max_Waves) return;
   if(!g_waves[w].used) return;
   int dir = g_waves[w].direction;

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
// ActiveWavePacketList 構築（Layer1専用の対外出力責務）
//+------------------------------------------------------------------+
WavePacket MakeEmptyPacket()
  {
   WavePacket p;
   p.wave_id          = 0;
   p.direction         = 0;
   p.fib0              = 0.0;
   p.structural_fib1   = 0.0;
   p.confirmed_bar_idx = -1;
   p.confirmed_bar_time= 0;
   p.recorded_accel    = 0.0;
   p.wave_stage        = STAGE_S4;
   p.is_fallback       = false;
   return p;
  }

void RebuildActiveWavePacketList(const datetime &time[])
  {
   if(ArraySize(g_active_packets) != Max_Waves)
      ArrayResize(g_active_packets, Max_Waves);

   for(int i = 0; i < Max_Waves; i++)
      g_active_packets[i] = MakeEmptyPacket();

   g_active_packet_count = 0;

   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].stage != STAGE_S3A && g_waves[w].stage != STAGE_S3B) continue;

      WavePacket p;
      p.wave_id            = g_waves[w].wave_id;
      p.direction           = g_waves[w].direction;
      p.fib0                = g_waves[w].fib0;
      p.structural_fib1     = g_waves[w].structural_fib1;
      p.confirmed_bar_idx   = g_waves[w].structural_fib1_confirmed_bar;
      int cb = p.confirmed_bar_idx;
      p.confirmed_bar_time  = (cb >= 0 && cb < ArraySize(time)) ? time[cb] : 0;
      p.recorded_accel      = g_waves[w].recorded_accel;
      p.wave_stage          = g_waves[w].stage;
      p.is_fallback         = g_waves[w].is_fallback;

      if(g_active_packet_count < Max_Waves)
        {
         g_active_packets[g_active_packet_count] = p;
         g_active_packet_count++;
        }
     }
  }

//+------------------------------------------------------------------+
// Fib1ライン + TP/SL描画（Layer1可視化）
//+------------------------------------------------------------------+
void DrawFibAndTPSL(int w, const datetime &time[])
  {
   if(w < 0 || w >= Max_Waves) return;
   if(!g_waves[w].used) return;
   int dir   = g_waves[w].direction;
   color clr = (dir == DIR_BUY) ? clrLime : clrOrangeRed;

   bool active = (g_waves[w].stage == STAGE_S3A || g_waves[w].stage == STAGE_S3B);

   if(ShowStructuralFib && active)
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

   //--- Wave番号: 常時表示要件。activeなら必ず描画する
   if(active)
     {
      string nw = g_waves[w].obj_wid;
      int sz = ArraySize(time);
      datetime label_t = (sz > 0) ? time[sz-1] : 0;
      string wid_txt = (dir==DIR_BUY?"W":"W") + IntegerToString(g_waves[w].wave_id) +
                       (g_waves[w].is_fallback ? "*" : "");
      if(ObjectFind(0, nw) < 0 && label_t > 0)
        {
         ObjectCreate(0, nw, OBJ_TEXT, 0, label_t, g_waves[w].structural_fib1);
         ObjectSetString (0, nw, OBJPROP_TEXT, wid_txt);
         ObjectSetInteger(0, nw, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, nw, OBJPROP_FONTSIZE, 9);
         ObjectSetString (0, nw, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, nw, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, nw, OBJPROP_SELECTABLE, false);
        }
      else if(label_t > 0)
        {
         ObjectMove(0, nw, 0, label_t, g_waves[w].structural_fib1);
         ObjectSetString(0, nw, OBJPROP_TEXT, wid_txt);
        }
     }
   else SafeDelete(g_waves[w].obj_wid);

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

   //--- TP/SL: structural_fib1(=1)を基準にFib拡張で算出
   // TP: 3段階(3.236 / 4.236 / 6.854) / SL: 構造起点基準(2.330)
   if(ShowTPSL && active)
     {
      double range = MathAbs(g_waves[w].structural_fib1 - g_waves[w].fib0);
      if(range <= 0) { // 安定性: range異常時は描画スキップしオブジェクトを残さない
         SafeDelete(g_waves[w].obj_tp1);
         SafeDelete(g_waves[w].obj_tp2);
         SafeDelete(g_waves[w].obj_tp3);
         SafeDelete(g_waves[w].obj_sl);
         return;
        }
      double tp1, tp2, tp3, sl;
      if(dir == DIR_BUY)
        {
         tp1 = g_waves[w].fib0 + 3.236 * range;
         tp2 = g_waves[w].fib0 + 4.236 * range;
         tp3 = g_waves[w].fib0 + 6.854 * range;
         sl  = g_waves[w].fib0 + 2.330 * range; // 認証帯下限を割ったら否定
        }
      else
        {
         tp1 = g_waves[w].fib0 - 3.236 * range;
         tp2 = g_waves[w].fib0 - 4.236 * range;
         tp3 = g_waves[w].fib0 - 6.854 * range;
         sl  = g_waves[w].fib0 - 2.330 * range;
        }

      string n1 = g_waves[w].obj_tp1;
      if(ObjectFind(0,n1)<0)
        {
         ObjectCreate(0,n1,OBJ_HLINE,0,0,tp1);
         ObjectSetInteger(0,n1,OBJPROP_COLOR,clrDodgerBlue);
         ObjectSetInteger(0,n1,OBJPROP_STYLE,STYLE_DASH);
         ObjectSetInteger(0,n1,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,n1,OBJPROP_SELECTABLE,false);
        }
      else ObjectSetDouble(0,n1,OBJPROP_PRICE,tp1);

      string n2 = g_waves[w].obj_tp2;
      if(ObjectFind(0,n2)<0)
        {
         ObjectCreate(0,n2,OBJ_HLINE,0,0,tp2);
         ObjectSetInteger(0,n2,OBJPROP_COLOR,clrMediumOrchid);
         ObjectSetInteger(0,n2,OBJPROP_STYLE,STYLE_DASH);
         ObjectSetInteger(0,n2,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,n2,OBJPROP_SELECTABLE,false);
        }
      else ObjectSetDouble(0,n2,OBJPROP_PRICE,tp2);

      string n3t = g_waves[w].obj_tp3;
      if(ObjectFind(0,n3t)<0)
        {
         ObjectCreate(0,n3t,OBJ_HLINE,0,0,tp3);
         ObjectSetInteger(0,n3t,OBJPROP_COLOR,clrGold);
         ObjectSetInteger(0,n3t,OBJPROP_STYLE,STYLE_DASH);
         ObjectSetInteger(0,n3t,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,n3t,OBJPROP_SELECTABLE,false);
        }
      else ObjectSetDouble(0,n3t,OBJPROP_PRICE,tp3);

      string n3 = g_waves[w].obj_sl;
      if(ObjectFind(0,n3)<0)
        {
         ObjectCreate(0,n3,OBJ_HLINE,0,0,sl);
         ObjectSetInteger(0,n3,OBJPROP_COLOR,clrCrimson);
         ObjectSetInteger(0,n3,OBJPROP_STYLE,STYLE_SOLID);
         ObjectSetInteger(0,n3,OBJPROP_WIDTH,2);
         ObjectSetInteger(0,n3,OBJPROP_SELECTABLE,false);
        }
      else ObjectSetDouble(0,n3,OBJPROP_PRICE,sl);
     }
   else
     {
      SafeDelete(g_waves[w].obj_tp1);
      SafeDelete(g_waves[w].obj_tp2);
      SafeDelete(g_waves[w].obj_tp3);
      SafeDelete(g_waves[w].obj_sl);
     }
  }

//+------------------------------------------------------------------+
// ============== LAYER 2: RCI (タイミング) ==============
// WavePacketのみを入力。Layer1内部状態には依存しない。
//+------------------------------------------------------------------+
double CalcRCI(const double &close[], int idx, int period, int total)
  {
   if(idx < period - 1 || idx >= total) return 0.0;
   double d2 = 0.0;
   for(int i = 0; i < period; i++)
     {
      int ci = idx - i;
      if(ci < 0 || ci >= total) return 0.0;
      double rt = (double)(i + 1);
      double rp = 1.0;
      for(int j = 0; j < period; j++)
        {
         int cj = idx - j;
         if(cj < 0 || cj >= total) continue;
         if(close[cj] < close[ci]) rp++;
        }
      double d = rt - rp;
      d2 += d*d;
     }
   double n = (double)period;
   return (1.0 - 6.0*d2/(n*(n*n-1.0))) * 100.0;
  }

// Layer2判定: RCIがダイバージェンスや極値滞在でないかを確認(参考情報)
string EvaluateRCIState(double rci_val)
  {
   if(rci_val > 80)  return "OVERHEAT";
   if(rci_val < -80) return "OVERCOLD";
   if(rci_val > 0)   return "UP";
   return "DOWN";
  }

//+------------------------------------------------------------------+
// ============== LAYER 3: MA (トレンド方向・MTF優先) ==============
//+------------------------------------------------------------------+
int EvaluateMAState(double price, double ma_val, double ma_higher_val)
  {
   // 上抜け維持=採用 / タッチ反発=継続 / 下抜け即復帰=ダマシ / 下抜け定着=崩壊
   bool above_cur    = (price > ma_val);
   bool above_higher  = (ma_higher_val > 0) ? (price > ma_higher_val) : above_cur;

   if(above_cur && above_higher) return MKT_TREND;
   if(!above_cur && !above_higher) return MKT_BREAK;
   return MKT_RANGE; // 上位足と下位足で不一致 = 過渡期
  }

//+------------------------------------------------------------------+
// ============== LAYER 4: VOLUME (補助確認のみ) ==============
// 構造否定はしない。参加率の参考情報としてのみ使用。
//+------------------------------------------------------------------+
bool EvaluateVolumeOK(const long &tick_volume[], int idx, int total)
  {
   if(!UseVolumeFilter) return true; // フィルタ無効時は常にOK
   if(idx < 10 || idx >= total) return true; // データ不足時は否定しない

   double avg = 0;
   int cnt = 0;
   for(int k = 1; k <= 10; k++)
     {
      int j = idx - k;
      if(j < 0) continue;
      avg += (double)tick_volume[j];
      cnt++;
     }
   if(cnt == 0) return true;
   avg /= cnt;
   if(avg <= 0) return true;

   double ratio = (double)tick_volume[idx] / avg;
   return (ratio >= Volume_MinRatio); // 補助情報。falseでも構造は否定しない
  }

//+------------------------------------------------------------------+
// 認証帯導出（WavePacketのみから計算）
//+------------------------------------------------------------------+
struct AuthZone
  {
   double init_low, init_high, term_low, term_high;
  };

AuthZone DeriveAuthZone(const WavePacket &p)
  {
   AuthZone z;
   double range = MathAbs(p.structural_fib1 - p.fib0);
   if(p.direction == DIR_BUY)
     {
      z.init_low  = p.fib0 + 2.330*range;
      z.init_high = p.fib0 + 2.618*range;
      z.term_low  = p.fib0 + 3.770*range;
      z.term_high = p.fib0 + 4.236*range;
     }
   else
     {
      z.init_low  = p.fib0 - 2.618*range;
      z.init_high = p.fib0 - 2.330*range;
      z.term_low  = p.fib0 - 4.236*range;
      z.term_high = p.fib0 - 3.770*range;
     }
   return z;
  }

void DrawAuthZoneLines(const WavePacket &p)
  {
   if(!ShowAuthZone) return;
   if(p.wave_stage != STAGE_S3A && p.wave_stage != STAGE_S3B) return;

   AuthZone z = DeriveAuthZone(p);
   string base = OBJ_PFX + "AUTH_W" + IntegerToString(p.wave_id) + "_";
   color clr = (p.direction == DIR_BUY) ? clrAqua : clrPink;

   string n1 = base + "LO", n2 = base + "HI";
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

//+------------------------------------------------------------------+
// 右上 統合状態パネル（Layer1〜4の結果を統合表示）
//+------------------------------------------------------------------+
void DrawStatePanel(int mkt_state, double rci_val, bool vol_ok)
  {
   if(!ShowStateLabel) { ObjectsDeleteAll(0, OBJ_PFX+"PANEL_"); return; }
   string base = OBJ_PFX + "PANEL_";

   string mkt_txt = (mkt_state==MKT_TREND) ? "TREND" :
                    (mkt_state==MKT_BREAK) ? "BREAK" : "RANGE";
   color  mkt_clr = (mkt_state==MKT_TREND) ? clrLime :
                    (mkt_state==MKT_BREAK) ? clrRed  : clrYellow;

   string rci_txt = EvaluateRCIState(rci_val);
   string vol_txt = vol_ok ? "OK" : "LOW";

   string t = base + "STATE";
   if(ObjectFind(0,t)<0) ObjectCreate(0,t,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,t,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,t,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,t,OBJPROP_YDISTANCE,10);
   ObjectSetString (0,t,OBJPROP_TEXT,
      StringFormat("MKT:%s  RCI:%s(%.0f)  VOL:%s", mkt_txt, rci_txt, rci_val, vol_txt));
   ObjectSetInteger(0,t,OBJPROP_COLOR,mkt_clr);
   ObjectSetInteger(0,t,OBJPROP_FONTSIZE,11);
   ObjectSetString (0,t,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,t,OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
// 右端 Wave一覧パネル（g_active_packetsのみを参照）
//+------------------------------------------------------------------+
void DrawWaveListPanel()
  {
   string base = OBJ_PFX + "LIST_";
   if(!ShowWaveList) { ObjectsDeleteAll(0, base); return; }

   string t = base + "TITLE";
   if(ObjectFind(0, t) < 0) ObjectCreate(0, t, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, t, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, t, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, t, OBJPROP_YDISTANCE, 10);
   ObjectSetString (0, t, OBJPROP_TEXT,      "== ACTIVE WAVES ==");
   ObjectSetInteger(0, t, OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, t, OBJPROP_FONTSIZE,  10);
   ObjectSetString (0, t, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, t, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, t, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);

   for(int i = 0; i < Max_Waves; i++)
      SafeDelete(base + "ROW" + IntegerToString(i));

   int y = 28, row = 0;
   for(int idx = 0; idx < g_active_packet_count; idx++)
     {
      WavePacket p = g_active_packets[idx];
      if(p.wave_id == 0) continue;

      AuthZone z = DeriveAuthZone(p);
      string dir_txt   = (p.direction == DIR_BUY) ? "BUY" : "SELL";
      string stage_txt = (p.wave_stage == STAGE_S3A) ? "S3A" : "S3B";
      string fb_txt     = p.is_fallback ? "[FB]" : "";
      color  line_clr   = (p.wave_stage == STAGE_S3A) ? clrLime : clrDodgerBlue;
      if(p.direction == DIR_SELL && p.wave_stage == STAGE_S3A) line_clr = clrOrangeRed;

      string txt = StringFormat("W%d %s %s%s SF1=%s",
                                p.wave_id, dir_txt, stage_txt, fb_txt,
                                DoubleToString(p.structural_fib1,_Digits));

      string rn = base + "ROW" + IntegerToString(row);
      ObjectCreate(0, rn, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, rn, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, rn, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, rn, OBJPROP_YDISTANCE, y);
      ObjectSetString (0, rn, OBJPROP_TEXT,      txt);
      ObjectSetInteger(0, rn, OBJPROP_COLOR,     line_clr);
      ObjectSetInteger(0, rn, OBJPROP_FONTSIZE,  9);
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

void UpdateDebugComment(int rates_total, int prev_calculated, double mkt_price)
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
      "TUTTO INDICATOR vFinal\n",
      "Bars=", rates_total, " prev=", prev_calculated, "\n",
      "S1=", s1, " S3A=", s3a, " S3B=", s3b, "\n",
      "ActivePackets=", g_active_packet_count
   );
  }

//+------------------------------------------------------------------+
// OnInit
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, DummyBuf, INDICATOR_CALCULATIONS);

   hATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   hMA  = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   hMA_Higher = iMA(_Symbol, MA_HigherTF, MA_Period, 0, MODE_SMA, PRICE_CLOSE);

   if(hATR == INVALID_HANDLE || hMA == INVALID_HANDLE || hMA_Higher == INVALID_HANDLE)
      return INIT_FAILED;

   ArrayResize(g_waves, Max_Waves);
   for(int i = 0; i < Max_Waves; i++)
     {
      g_waves[i].used = false;
      g_waves[i].obj_sf = ""; g_waves[i].obj_df = "";
      g_waves[i].obj_tp1 = ""; g_waves[i].obj_tp2 = ""; g_waves[i].obj_tp3 = "";
      g_waves[i].obj_sl = ""; g_waves[i].obj_wid = "";
      g_waves[i].is_parent = false;
      g_waves[i].is_fallback = false;
     }
   ArrayResize(g_active_packets, Max_Waves);
   for(int i = 0; i < Max_Waves; i++)
      g_active_packets[i] = MakeEmptyPacket();
   g_active_packet_count = 0;

   for(int i = 0; i < 2; i++) g_last_dead[i].valid = false;

   InitTFParams();
   g_last_bar = 0;
   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO vFinal");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hMA  != INVALID_HANDLE) IndicatorRelease(hMA);
   if(hMA_Higher != INVALID_HANDLE) IndicatorRelease(hMA_Higher);
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
   int min_req = ATR_Period + MA_Period + fl*8 + 10;

   if(rates_total < min_req)
     {
      Comment("TUTTO vFinal waiting... (", rates_total, "/", min_req, ")");
      return 0;
     }

   double atr_tmp[1];
   if(CopyBuffer(hATR, 0, 1, 1, atr_tmp) > 0)
      g_atr_last = atr_tmp[0];

   datetime cur_bar_time = time[rates_total - 2];
   bool new_bar = (cur_bar_time != g_last_bar);

   if(!new_bar)
     {
      UpdateDebugComment(rates_total, prev_calculated, close[rates_total-2]);
      return prev_calculated;
     }
   g_last_bar = cur_bar_time;

   if(g_atr_last <= 0.0)
     {
      UpdateDebugComment(rates_total, prev_calculated, close[rates_total-2]);
      return prev_calculated;
     }

   int start = (prev_calculated > 1) ? prev_calculated - 1 : min_req;

   int need = rates_total - start + fl + 2;
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   int got = CopyBuffer(hATR, 0, 0, need, atr_buf);
   if(got <= 0)
     {
      UpdateDebugComment(rates_total, prev_calculated, close[rates_total-2]);
      return prev_calculated;
     }

   //================================================================
   // LAYER 1: Wave構造検出 + フォールバック保証
   //================================================================
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

      // 親波死亡防止: 各方向で親波が存在しなければ子波を昇格
      EnsureParentWave(DIR_BUY);
      EnsureParentWave(DIR_SELL);
     }

   //--- Layer1可視化
   for(int w = 0; w < Max_Waves; w++)
      DrawFibAndTPSL(w, time);

   //--- 観測バッファ層構築（Layer1 → Layer2/3/4 出力）
   RebuildActiveWavePacketList(time);

   //================================================================
   // LAYER 2: RCI / LAYER 3: MA / LAYER 4: Volume
   //================================================================
   double ma_buf[1], ma_h_buf[1];
   double ma_val = 0, ma_higher_val = 0;
   if(CopyBuffer(hMA, 0, 1, 1, ma_buf) > 0) ma_val = ma_buf[0];
   if(CopyBuffer(hMA_Higher, 0, 1, 1, ma_h_buf) > 0) ma_higher_val = ma_h_buf[0];

   double cur_price = close[rates_total - 2];
   double rci_val = CalcRCI(close, rates_total - 2, RCI_Period, rates_total);
   int mkt_state  = EvaluateMAState(cur_price, ma_val, ma_higher_val);
   bool vol_ok    = EvaluateVolumeOK(tick_volume, rates_total - 2, rates_total);

   for(int idx = 0; idx < g_active_packet_count; idx++)
     {
      WavePacket p = g_active_packets[idx];
      if(p.wave_id == 0) continue;
      DrawAuthZoneLines(p);
     }

   DrawWaveListPanel();
   DrawStatePanel(mkt_state, rci_val, vol_ok);

   UpdateDebugComment(rates_total, prev_calculated, cur_price);
   ChartRedraw(0);
   return rates_total;
  }
