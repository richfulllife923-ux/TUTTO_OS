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
input int    Retention_Generations = 300; // Object GC: 軌跡矢印の保持世代数
input int    Ghost_History_Capacity = 1500; // GhostWave母集団の最大保持件数

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
   int      tier;               // TIER_ACTIVE / TIER_DORMANT / TIER_STALE
  };

// 固定サイズ配列。未使用スロットは wave_id==0 で無効化
WavePacket g_active_packets[];
int        g_active_packet_count = 0;

//+------------------------------------------------------------------+
// GhostStats — GhostWave統計結果(TuttoWaveのキャッシュフィールドで
// 使用するため、TuttoWaveより前に定義する)
//+------------------------------------------------------------------+
struct GhostStats
  {
   bool   valid;
   int    sample_count;
   double reach_TP1_rate;   // reach_ratio >= 3.236 に到達した割合
   double reach_TP2_rate;   // reach_ratio >= 4.236 に到達した割合
   double reach_TP3_rate;   // reach_ratio >= 6.854 に到達した割合
   double avg_reach_ratio;  // 平均到達倍率
   double avg_similarity;   // 採用された履歴群の平均類似度(0〜100%)
  };

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

   // Wave寿命モデル(TIERシステム)
   int      tier;                // TIER_ACTIVE / TIER_DORMANT / TIER_STALE
   int      last_update_bar;     // structural_fib1が最後に更新されたバー
   int      generation;          // 生成順序(GC・LRU比較に使用)

   // GhostStatsキャッシュ(軽量化): 新規Ghost死亡時(g_ghost_history_version変化時)
   // または自身のheld/accelが変化した時のみ再計算する
   bool       ghost_cache_valid;
   int        ghost_cache_history_version;
   int        ghost_cache_held;
   double     ghost_cache_accel;
   GhostStats ghost_cache_value;

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

// TIER定数(Wave寿命モデル)
#define TIER_ACTIVE   0
#define TIER_DORMANT  1
#define TIER_STALE    2

// 親波構成のダーティフラグ(EnsureParentWave軽量化用)
bool g_parent_dirty[2] = {true, true}; // [0]=BUY, [1]=SELL

int g_generation_counter = 0; // 単調増加するWorld Generation
int g_last_gc_generation = 0; // 最後にGCを実行した世代(差分GC用)

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

//+------------------------------------------------------------------+
// GhostHistory — GhostWave統計エンジンの母集団データ
// waveが死亡(KillWave/KillWaveSilent)した時点の特徴量を記録する
// これは「未来予測」ではなく「過去に起きた事実」の記録である
//+------------------------------------------------------------------+
struct GhostHistory
  {
   bool     valid;
   int      direction;
   double   fib0;
   double   final_structural_fib1;  // 死亡時点でのstructural_fib1
   double   range;                  // |final_structural_fib1 - fib0|
   int      duration;               // HL確定からHH確定までの保有期間
   double   accel_score;            // 記録されたaccel
   double   reach_ratio;            // 死亡時close を fib0基準で正規化した到達倍率
                                     // (TP1=3.236, TP2=4.236, TP3=6.854 のどこまで
                                     //  到達したかを示す統計値。予測ではなく結果)
   int      generation;             // 記録された世代(時間フィルタ用)
   int      death_bar_idx;
  };

// 固定長リングバッファ。新しい履歴が古い履歴を上書きする(無限蓄積防止)
GhostHistory g_ghost_history[];
int          g_ghost_history_count = 0; // 現在の有効件数(リングバッファ充填数)
int          g_ghost_history_head  = 0; // 次に書き込むインデックス
int          g_ghost_history_version = 0; // 新規Ghost記録時のみ増加(キャッシュ無効化用)

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
// Wave寿命モデル: TIER判定（CalcTier）
// ACTIVE  = 直近g_required_bars*3以内にstructural_fib1が更新
// DORMANT = それより古いが、Dynamic Fib1はまだ動いている
// STALE   = 長期間(g_required_bars*10以上)更新がない実質死に体
//+------------------------------------------------------------------+
int CalcTier(int w, int cur_bar_idx)
  {
   if(w < 0 || w >= Max_Waves) return TIER_STALE;
   int since_update = cur_bar_idx - g_waves[w].last_update_bar;
   int active_th = g_required_bars * 3;
   int stale_th  = g_required_bars * 10;
   if(since_update <= active_th) return TIER_ACTIVE;
   if(since_update <= stale_th)  return TIER_DORMANT;
   return TIER_STALE;
  }

//+------------------------------------------------------------------+
// LRU退場: Max_Waves満杯時、最もSTALEなwaveを退場させる
// 入れ替え条件は保守的: 既存最弱がSTALEである場合のみ実行
// (「強い波が居座る」誤退場を避けるため、無条件入れ替えはしない)
//+------------------------------------------------------------------+
int FindEvictionCandidate(int cur_bar_idx)
  {
   int worst_w = -1;
   int worst_tier = -1;
   int worst_age = -1;

   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].is_parent) continue; // 親波は退場対象から除外(安定性優先)

      int t = CalcTier(w, cur_bar_idx);
      int age = cur_bar_idx - g_waves[w].last_update_bar;

      // STALEを最優先、同TIERならより古い(age大)ものを優先
      if(t > worst_tier || (t == worst_tier && age > worst_age))
        {
         worst_tier = t;
         worst_age  = age;
         worst_w    = w;
        }
     }

   // STALEのみを退場対象とする(保守的条件)
   if(worst_w >= 0 && worst_tier == TIER_STALE) return worst_w;
   return -1;
  }

//+------------------------------------------------------------------+
// WAVE管理（破綻防止: 配列範囲チェック・未初期化排除）
//+------------------------------------------------------------------+
int AllocWave(int dir, double fib0v, int fib0i, bool fallback)
  {
   if(fib0i < 0) return -1; // 安全ガード

   int slot = -1;
   for(int i = 0; i < Max_Waves; i++)
      if(!g_waves[i].used) { slot = i; break; }

   // 満杯時: LRU退場を試みる(要件4: Max_Waves制約突破)
   if(slot < 0)
     {
      int victim = FindEvictionCandidate(fib0i);
      if(victim >= 0)
        {
         KillWaveSilent(victim); // 描画も含めて静かに退場(GC対象として記録)
         slot = victim;
        }
      else
        return -1; // 退場候補なし。満杯のまま新規生成を見送る
     }

   {
      int i = slot;
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
      g_waves[i].tier                          = TIER_ACTIVE;
      g_waves[i].last_update_bar               = fib0i;
      g_waves[i].generation                    = g_generation_counter++;
      g_waves[i].ghost_cache_valid              = false;
      g_waves[i].wave_id                       = g_next_id++;
      string b = OBJ_PFX + "G" + IntegerToString(g_waves[i].generation) +
                 "_W" + IntegerToString(g_waves[i].wave_id) + "_";
      g_waves[i].obj_sf  = b + "SF";
      g_waves[i].obj_df  = b + "DF";
      g_waves[i].obj_tp1 = b + "TP1";
      g_waves[i].obj_tp2 = b + "TP2";
      g_waves[i].obj_tp3 = b + "TP3";
      g_waves[i].obj_sl  = b + "SL";
      g_waves[i].obj_wid = b + "WID";
      g_parent_dirty[(dir==DIR_BUY)?0:1] = true; // 新規生成 → dirty化
      return i;
     }
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

//+------------------------------------------------------------------+
// GhostWave母集団への記録（死亡時点で1回のみ実行）
// 母集団定義(確定済み):
//   Step1: Fib0→Fib1成立(impulse2_done==1) + structural_fib1更新履歴あり
//   Step2: 直近N世代に時間制限(Ghost_History_Capacityのリングバッファで実現)
//   Step3: duration/accel_scoreによる類似度フィルタ(検索時に適用)
// → ここでは記録のみ行う。類似度判定はGhostWave検索関数側で行う
//+------------------------------------------------------------------+
void RecordGhostHistory(int w, double death_close)
  {
   if(w < 0 || w >= Max_Waves) return;
   if(g_waves[w].impulse2_done != 1) return; // Step1: Fib0→Fib1未成立は対象外
   double range = MathAbs(g_waves[w].structural_fib1 - g_waves[w].fib0);
   if(range <= 0) return;

   if(ArraySize(g_ghost_history) != Ghost_History_Capacity)
      ArrayResize(g_ghost_history, Ghost_History_Capacity);

   GhostHistory h;
   h.valid                 = true;
   h.direction              = g_waves[w].direction;
   h.fib0                   = g_waves[w].fib0;
   h.final_structural_fib1  = g_waves[w].structural_fib1;
   h.range                  = range;
   // duration: hl_candidate確定からstructural_fib1確定までの保有期間
   h.duration               = g_waves[w].structural_fib1_idx - g_waves[w].hl_candidate_idx;
   if(h.duration < 0) h.duration = 0;
   h.accel_score             = g_waves[w].recorded_accel;
   // reach_ratio: 死亡時の価格をfib0基準・range単位で正規化した到達倍率
   // (3.236/4.236/6.854等のTUTTO拡張値と同じ尺度で比較できる)
   double raw = (g_waves[w].direction == DIR_BUY)
                ? (death_close - g_waves[w].fib0) / range
                : (g_waves[w].fib0 - death_close) / range;
   h.reach_ratio             = raw;
   h.generation              = g_waves[w].generation;
   h.death_bar_idx           = g_waves[w].structural_fib1_idx;

   // リングバッファに書き込み(古い履歴を上書き)
   g_ghost_history[g_ghost_history_head] = h;
   g_ghost_history_head = (g_ghost_history_head + 1) % Ghost_History_Capacity;
   if(g_ghost_history_count < Ghost_History_Capacity)
      g_ghost_history_count++;
   g_ghost_history_version++; // キャッシュ無効化トリガー
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
      g_parent_dirty[slot] = true; // 親波消失 → EnsureParentWave再実行が必要
     }

   RecordGhostHistory(w, death_price); // GhostWave母集団へ記録
   DeleteWaveVisuals(w);
   g_waves[w].used  = false;
   g_waves[w].stage = STAGE_S4;
  }

//+------------------------------------------------------------------+
// LRU退場専用: 死亡矢印を残さず静かにスロットを解放する
// (Max_Waves満杯時の容量管理用。価格条件によるDEATH-1とは無関係)
//+------------------------------------------------------------------+
void KillWaveSilent(int w)
  {
   if(w < 0 || w >= Max_Waves) return;
   if(!g_waves[w].used) return;

   if(g_waves[w].is_parent)
     {
      int slot = (g_waves[w].direction == DIR_BUY) ? 0 : 1;
      g_parent_dirty[slot] = true;
     }

   // LRU退場(老化による自然死)もGhostWave母集団に記録する
   // 死亡時点の明示的な価格引数がないため、dynamic_fib1(直近の到達点)を
   // 代理値として使用する(=「最後にここまで到達して力尽きた」という事実)
   RecordGhostHistory(w, g_waves[w].dynamic_fib1);
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
            string n = OBJ_PFX + "S1_G" + IntegerToString(g_waves[slot].generation)
                       + "_" + IntegerToString(g_waves[slot].wave_id);
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
            string n = OBJ_PFX + "S1_G" + IntegerToString(g_waves[slot].generation)
                       + "_" + IntegerToString(g_waves[slot].wave_id);
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
   int slot = (dir == DIR_BUY) ? 0 : 1;
   if(!g_parent_dirty[slot]) return; // 軽量化: 変化がなければO(1)で即return

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

   g_parent_dirty[slot] = false; // スキャン完了 → クリーン化
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
         string n = OBJ_PFX + "HL_G" + IntegerToString(g_waves[w].generation)
                    + "_" + IntegerToString(g_waves[w].wave_id);
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
         g_waves[w].last_update_bar                 = hh_idx; // 寿命モデル: 更新時刻記録
         g_waves[w].tier                            = TIER_ACTIVE;

         string n = OBJ_PFX + "S3A_G" + IntegerToString(g_waves[w].generation)
                    + "_" + IntegerToString(g_waves[w].wave_id)
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

   // 寿命モデル: TIER再計算(毎バー)
   g_waves[w].tier = CalcTier(w, bar_idx);

   // STALE強制DEATH: 親波以外がSTALEに達したら世代交代として退場
   // (DEATH-1とは独立した、老化による自然退場の経路)
   //
   // 重要: STAGE_S3B(再認証試行中)はSTALE判定の対象から除外する
   // 再認証中はstructural_fib1を更新しないため(設計仕様)
   // last_update_barが古いまま固定されSTALEになりやすいが
   // これは「老化」ではなく「再認証プロセスの進行中」であり
   // 寿命モデルによる強制退場の対象にしてはならない
   // (S3Bの退場判定はEvaluateTransitions内のs3b_max_waitタイムアウトに委ねる)
   if(g_waves[w].tier == TIER_STALE && !g_waves[w].is_parent &&
      g_waves[w].stage != STAGE_S3B)
     {
      KillWaveSilent(w);
      return;
     }

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

         string n = OBJ_PFX + "S3B_G" + IntegerToString(g_waves[w].generation)
                    + "_" + IntegerToString(g_waves[w].wave_id)
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
   p.tier               = TIER_STALE;
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
      p.tier                 = g_waves[w].tier;

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
// ============== LAYER 5: HEATMAP (市場密度可視化) ==============
// 価格帯ごとの構造発生密度(S1/HL/S3A頻度)を可視化する
// これは「予測」ではなく「過去〜現在の発生頻度の集計」である
//+------------------------------------------------------------------+
input bool   ShowHeatMap        = true;
input int    HeatMap_BinCount   = 24;     // 価格帯の分割数
input int    HeatMap_LookbackBars = 500;  // 集計対象バー数
input int    HeatMap_RangeRecalcInterval = 20; // 価格レンジ再計算の間隔(バー数)

struct HeatBin
  {
   double price_low, price_high;
   int    s1_count;
   int    hl_count;
   int    s3a_count;       // 認証済み・子波
   int    s3b_count;       // 再検証中(Fail帯候補)・子波
   int    parent_count;    // 親波(is_parent==true)の存在数
  };
HeatBin g_heat_bins[];

// 軽量化: 価格レンジ(range_high/range_low)はHeatMap_RangeRecalcInterval
// バーごとにのみ再計算する。500本の全走査を毎バー行うのではなく
// 間隔を空けることで負荷を大幅に削減する(レンジは短期間では
// ほとんど変化しないため、近似として十分な精度を保てる)
double   g_heat_range_high = 0, g_heat_range_low = 0;
int      g_heat_last_recalc_bar = -1000000;

//+------------------------------------------------------------------+
// Geometry HeatMap集計: 価格の密集ではなく「波の採用密度」を表す
// Parent/Child、S3A(認証済み)/S3B(再検証中=Fail帯候補)を区別する
//+------------------------------------------------------------------+
void RebuildHeatMap(const double &high[], const double &low[], int rates_total)
  {
   if(!ShowHeatMap) return;
   int total = rates_total;
   int look_end = total - 2;
   if(look_end < 0) return;

   // 軽量化: レンジ再計算は間隔を空けて実行(毎バー500本走査を回避)
   bool need_recalc = (g_heat_range_high <= g_heat_range_low) ||
                      (look_end - g_heat_last_recalc_bar >= HeatMap_RangeRecalcInterval);

   if(need_recalc)
     {
      int look_start = total - 2 - HeatMap_LookbackBars;
      if(look_start < 0) look_start = 0;

      double range_high = -DBL_MAX, range_low = DBL_MAX;
      for(int i = look_start; i <= look_end; i++)
        {
         if(high[i] > range_high) range_high = high[i];
         if(low[i]  < range_low)  range_low  = low[i];
        }
      if(range_high <= range_low) return;

      g_heat_range_high = range_high;
      g_heat_range_low  = range_low;
      g_heat_last_recalc_bar = look_end;
     }

   double range_high = g_heat_range_high;
   double range_low  = g_heat_range_low;
   if(range_high <= range_low) return;

   if(ArraySize(g_heat_bins) != HeatMap_BinCount)
      ArrayResize(g_heat_bins, HeatMap_BinCount);

   double bin_size = (range_high - range_low) / HeatMap_BinCount;
   for(int b = 0; b < HeatMap_BinCount; b++)
     {
      g_heat_bins[b].price_low    = range_low + bin_size * b;
      g_heat_bins[b].price_high   = range_low + bin_size * (b+1);
      g_heat_bins[b].s1_count      = 0;
      g_heat_bins[b].hl_count      = 0;
      g_heat_bins[b].s3a_count     = 0;
      g_heat_bins[b].s3b_count     = 0;
      g_heat_bins[b].parent_count  = 0;
     }

   // 現在保持しているwave構造の特徴点を集計(used==trueのみ)
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;

      double fib0_price = g_waves[w].fib0;
      for(int b = 0; b < HeatMap_BinCount; b++)
         if(fib0_price >= g_heat_bins[b].price_low && fib0_price < g_heat_bins[b].price_high)
           { g_heat_bins[b].s1_count++; break; }

      if(g_waves[w].impulse1_done == 1)
        {
         double hl_price = g_waves[w].hl_candidate;
         for(int b = 0; b < HeatMap_BinCount; b++)
            if(hl_price >= g_heat_bins[b].price_low && hl_price < g_heat_bins[b].price_high)
              { g_heat_bins[b].hl_count++; break; }
        }

      // S3A(認証済み=採用帯)とS3B(再検証中=Fail帯候補)を分離して集計
      if(g_waves[w].stage == STAGE_S3A || g_waves[w].stage == STAGE_S3B)
        {
         double sf_price = g_waves[w].structural_fib1;
         for(int b = 0; b < HeatMap_BinCount; b++)
           {
            if(sf_price >= g_heat_bins[b].price_low && sf_price < g_heat_bins[b].price_high)
              {
               if(g_waves[w].stage == STAGE_S3A) g_heat_bins[b].s3a_count++;
               else                              g_heat_bins[b].s3b_count++;
               if(g_waves[w].is_parent) g_heat_bins[b].parent_count++;
               break;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
// HeatMap可視化: 右側に密度バーを描画(色=密度、長さ=相対頻度)
// 青(弱い構造)→黄(中立)→オレンジ(警戒)→赤(高密度=構造集中)
//+------------------------------------------------------------------+
color HeatColorFromDensity(double normalized) // 0.0〜1.0
  {
   if(normalized < 0.25) return clrDodgerBlue;
   if(normalized < 0.50) return clrYellow;
   if(normalized < 0.75) return clrOrange;
   return clrRed;
  }

void DrawHeatMap(const datetime &time[], int rates_total)
  {
   string pfx = OBJ_PFX + "HEAT_";
   if(!ShowHeatMap) { ObjectsDeleteAll(0, pfx); return; }
   if(ArraySize(g_heat_bins) == 0) return;

   int max_total = 0;
   for(int b = 0; b < HeatMap_BinCount; b++)
     {
      int t = g_heat_bins[b].s1_count + g_heat_bins[b].hl_count +
              g_heat_bins[b].s3a_count + g_heat_bins[b].s3b_count;
      if(t > max_total) max_total = t;
     }
   if(max_total <= 0) { ObjectsDeleteAll(0, pfx); return; }

   datetime t_anchor = time[rates_total-2];
   datetime t_end = t_anchor + (datetime)(PeriodSeconds(PERIOD_CURRENT) * 20);

   for(int b = 0; b < HeatMap_BinCount; b++)
     {
      int t = g_heat_bins[b].s1_count + g_heat_bins[b].hl_count +
              g_heat_bins[b].s3a_count + g_heat_bins[b].s3b_count;
      double norm = (double)t / max_total;
      string n = pfx + IntegerToString(b);
      if(t <= 0) { SafeDelete(n); continue; }

      if(ObjectFind(0, n) < 0)
        {
         ObjectCreate(0, n, OBJ_RECTANGLE, 0,
                      t_anchor, g_heat_bins[b].price_low,
                      t_end,    g_heat_bins[b].price_high);
         ObjectSetInteger(0, n, OBJPROP_BACK, true);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, n, OBJPROP_FILL, true);
        }
      else
        {
         ObjectSetInteger(0, n, OBJPROP_TIME, 0, t_anchor);
         ObjectSetDouble  (0, n, OBJPROP_PRICE, 0, g_heat_bins[b].price_low);
         ObjectSetInteger(0, n, OBJPROP_TIME, 1, t_end);
         ObjectSetDouble  (0, n, OBJPROP_PRICE, 1, g_heat_bins[b].price_high);
        }
      ObjectSetInteger(0, n, OBJPROP_COLOR, HeatColorFromDensity(norm));
     }
  }

//+------------------------------------------------------------------+
// ============== LAYER 6: GHOSTWAVE (統計遷移場) ==============
// 重要: 未来予測ではない。過去の同構造Wave群が「結果として」
// どこまで到達したかを集計し、統計分布として提示するのみ。
//
// 母集団定義(確定済み):
//   Step1: Fib0→Fib1成立wave(RecordGhostHistoryで記録済み)
//   Step2: 直近N件に時間制限(リングバッファ容量Ghost_History_Capacityで実現)
//   Step3: duration + accel_scoreの近似度で類似クラスタ化
//+------------------------------------------------------------------+
input bool   ShowGhostWave        = true;
input double Ghost_Duration_Tolerance = 0.5;  // duration類似許容比率(±50%)
input double Ghost_Accel_Tolerance    = 0.3;  // accel_score類似許容差(絶対値)
input int    Ghost_Min_Samples         = 5;    // 統計を表示する最小サンプル数

//+------------------------------------------------------------------+
// 類似度スコア(連続値0〜100%): durationとaccel_scoreの誤差から算出
// 値が大きいほど「現在の構造的特徴」と「過去の履歴」が近い
//+------------------------------------------------------------------+
double CalcGhostSimilarity(int duration, double accel, const GhostHistory &h)
  {
   if(!h.valid || duration <= 0) return 0;

   double dur_ratio_diff = MathAbs((double)(h.duration - duration)) /
                            MathMax((double)duration, 1.0);
   double dur_score = MathMax(0.0, 1.0 - dur_ratio_diff / Ghost_Duration_Tolerance);

   double accel_diff = MathAbs(h.accel_score - accel);
   double accel_score_norm = MathMax(0.0, 1.0 - accel_diff / Ghost_Accel_Tolerance);

   return ((dur_score + accel_score_norm) / 2.0) * 100.0;
  }

//+------------------------------------------------------------------+
// 類似度判定(採用/非採用の2値): 連続スコアが0を超えるもののみ母集団に含める
// (duration/accel双方の許容誤差を超えたものはスコア0として自動除外される)
//+------------------------------------------------------------------+
bool IsSimilarGhost(int duration, double accel, const GhostHistory &h)
  {
   return CalcGhostSimilarity(duration, accel, h) > 0.0;
  }

//+------------------------------------------------------------------+
// 現在のwave(進行中)に対して、類似する過去履歴群から統計を集計する
// これが「結果分布」であり、個別の未来予測ではない
//+------------------------------------------------------------------+
GhostStats CalcGhostStats(int duration, double accel, int direction)
  {
   GhostStats s;
   s.valid           = false;
   s.sample_count     = 0;
   s.reach_TP1_rate    = 0;
   s.reach_TP2_rate    = 0;
   s.reach_TP3_rate    = 0;
   s.avg_reach_ratio   = 0;
   s.avg_similarity    = 0;

   double sum_reach = 0;
   double sum_similarity = 0;
   int    cnt_tp1 = 0, cnt_tp2 = 0, cnt_tp3 = 0;

   int n = ArraySize(g_ghost_history);
   for(int i = 0; i < n; i++)
     {
      if(!g_ghost_history[i].valid) continue;
      if(g_ghost_history[i].direction != direction) continue;
      double sim = CalcGhostSimilarity(duration, accel, g_ghost_history[i]);
      if(sim <= 0.0) continue;

      s.sample_count++;
      sum_reach += g_ghost_history[i].reach_ratio;
      sum_similarity += sim;
      if(g_ghost_history[i].reach_ratio >= 3.236) cnt_tp1++;
      if(g_ghost_history[i].reach_ratio >= 4.236) cnt_tp2++;
      if(g_ghost_history[i].reach_ratio >= 6.854) cnt_tp3++;
     }

   if(s.sample_count < Ghost_Min_Samples) return s; // サンプル不足。validはfalseのまま

   s.valid           = true;
   s.avg_reach_ratio  = sum_reach / s.sample_count;
   s.avg_similarity   = sum_similarity / s.sample_count;
   s.reach_TP1_rate    = (double)cnt_tp1 / s.sample_count;
   s.reach_TP2_rate    = (double)cnt_tp2 / s.sample_count;
   s.reach_TP3_rate    = (double)cnt_tp3 / s.sample_count;
   return s;
  }

//+------------------------------------------------------------------+
// GhostStatsキャッシュ取得(軽量化): wave単位でキャッシュし
// 「新規Ghost死亡時(version変化)」または「自身のheld/accelが
// 変化した時」のみ実際にCalcGhostStats(全履歴走査)を再実行する
// それ以外のティック・バーでは保存済みの値を即座に返す
//+------------------------------------------------------------------+
GhostStats GetCachedGhostStats(int w, int held, double accel, int direction)
  {
   GhostStats empty;
   empty.valid = false; empty.sample_count = 0;
   empty.reach_TP1_rate = 0; empty.reach_TP2_rate = 0; empty.reach_TP3_rate = 0;
   empty.avg_reach_ratio = 0; empty.avg_similarity = 0;
   if(w < 0 || w >= Max_Waves) return empty;

   bool cache_ok = g_waves[w].ghost_cache_valid &&
                   g_waves[w].ghost_cache_history_version == g_ghost_history_version &&
                   g_waves[w].ghost_cache_held == held &&
                   MathAbs(g_waves[w].ghost_cache_accel - accel) < 0.0001;

   if(cache_ok) return g_waves[w].ghost_cache_value;

   GhostStats fresh = CalcGhostStats(held, accel, direction);
   g_waves[w].ghost_cache_valid            = true;
   g_waves[w].ghost_cache_history_version  = g_ghost_history_version;
   g_waves[w].ghost_cache_held              = held;
   g_waves[w].ghost_cache_accel             = accel;
   g_waves[w].ghost_cache_value             = fresh;
   return fresh;
  }

//+------------------------------------------------------------------+
// GhostWave可視化: TP1/2/3ラベルに到達率(統計値)を追記する
// 「未来線」ではなく、既存のTP/SLラインへの統計注記として表示する
//+------------------------------------------------------------------+
void DrawGhostWaveLabel(int w, const datetime &time[], int last_idx)
  {
   string n = OBJ_PFX + "GHOST_W" + IntegerToString(g_waves[w].wave_id);
   if(!ShowGhostWave || g_waves[w].stage != STAGE_S3A)
     {
      SafeDelete(n);
      return;
     }

   int held = g_waves[w].structural_fib1_idx - g_waves[w].hl_candidate_idx;
   if(held < 0) held = 0;
   GhostStats gs = GetCachedGhostStats(w, held, g_waves[w].recorded_accel, g_waves[w].direction);
   if(!gs.valid) { SafeDelete(n); return; }

   string txt = StringFormat("Ghost Similarity %.0f%% | Sample %d | TP1:%.0f%% TP2:%.0f%% TP3:%.0f%%",
                             gs.avg_similarity, gs.sample_count,
                             gs.reach_TP1_rate*100, gs.reach_TP2_rate*100, gs.reach_TP3_rate*100);

   if(last_idx < 0 || last_idx >= ArraySize(time)) { SafeDelete(n); return; }
   double label_price = g_waves[w].structural_fib1;
   color clr = (g_waves[w].direction == DIR_BUY) ? clrAqua : clrViolet;

   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_TEXT, 0, time[last_idx], label_price);
      ObjectSetString (0, n, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
      ObjectSetString (0, n, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
     }
   else
     {
      ObjectMove(0, n, 0, time[last_idx], label_price);
      ObjectSetString(0, n, OBJPROP_TEXT, txt);
     }
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
// ============== LAYER 7: SCORE ENGINE (構造採用スコア) ==============
// 「今のWaveが市場に採用されている度合い」を0〜100で数値化する。
// これは売買判断そのものではなく、構造の信頼度を示す補助指標。
//
// 入力:
//   TIER状態        (重み30): ACTIVE=満点, DORMANT=半分, STALE=0
//   GhostWave一致度  (重み30): 統計サンプル十分かつ高到達率なら加点
//   HeatMap密度      (重み20): その価格帯の構造発生密度が高いほど加点
//   MA構造位置       (重み20): TREND一致なら満点、RANGE半分、BREAK0
//+------------------------------------------------------------------+
double ScoreFromTier(int tier)
  {
   if(tier == TIER_ACTIVE)  return 1.0;
   if(tier == TIER_DORMANT) return 0.5;
   return 0.0; // TIER_STALE
  }

double ScoreFromGhost(const GhostStats &gs)
  {
   if(!gs.valid) return 0.5; // サンプル不足時は中立(否定も肯定もしない)
   // TP1到達率を主指標とする(到達率が高いほど「この構造は伸びやすかった」)
   return MathMin(gs.reach_TP1_rate, 1.0);
  }

double ScoreFromHeat(double wave_price, int rates_total_unused)
  {
   if(ArraySize(g_heat_bins) == 0) return 0.5; // データなし時は中立

   int max_total = 0;
   int this_total = 0;
   for(int b = 0; b < HeatMap_BinCount; b++)
     {
      int t = g_heat_bins[b].s1_count + g_heat_bins[b].hl_count +
              g_heat_bins[b].s3a_count + g_heat_bins[b].s3b_count;
      if(t > max_total) max_total = t;
      if(wave_price >= g_heat_bins[b].price_low && wave_price < g_heat_bins[b].price_high)
         this_total = t;
     }
   if(max_total <= 0) return 0.5;
   return (double)this_total / max_total;
  }

//+------------------------------------------------------------------+
// Parent Strength Score（複合指標・確定仕様）
// 目的: 「最も大きい波」ではなく「市場が現在採用している波」を検出する
//
// 40% Range Strength    = ATR絶対強度70% + 同方向内相対強度30%
// 30% Adoption Freshness = last_update_barの新しさ(g_required_bars基準)
// 20% Tier State         = ACTIVE=100 / DORMANT=50 / STALE=0
// 10% Parent Status      = is_parent ? 100 : 0
//+------------------------------------------------------------------+

// 同方向の全アクティブwaveの中での最大range(相対評価の基準)
double CalcMaxActiveRange(int direction)
  {
   double max_range = 0;
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].direction != direction) continue;
      if(g_waves[w].stage != STAGE_S3A && g_waves[w].stage != STAGE_S3B) continue;
      double r = MathAbs(g_waves[w].structural_fib1 - g_waves[w].fib0);
      if(r > max_range) max_range = r;
     }
   return max_range;
  }

double CalcRangeStrength(int w, double atr_val, double max_active_range)
  {
   if(w < 0 || w >= Max_Waves) return 0;
   double range = MathAbs(g_waves[w].structural_fib1 - g_waves[w].fib0);

   double atr_strength = 0;
   if(atr_val > 0)
      atr_strength = MathMin(100.0, (range / (atr_val * 10.0)) * 100.0);

   double relative_strength = 0;
   if(max_active_range > 0)
      relative_strength = (range / max_active_range) * 100.0;

   return atr_strength*0.7 + relative_strength*0.3;
  }

double CalcAdoptionFreshness(int w, int cur_bar_idx)
  {
   if(w < 0 || w >= Max_Waves) return 0;
   int since_update = cur_bar_idx - g_waves[w].last_update_bar;
   double stale_th = (double)(g_required_bars * 10); // CalcTierのSTALE閾値と一貫
   if(stale_th <= 0) return 0;
   double freshness = 100.0 * (1.0 - (double)since_update / stale_th);
   return MathMax(0.0, MathMin(100.0, freshness));
  }

double CalcParentStrengthEx(int w, double atr_val, int cur_bar_idx, double max_active_range)
  {
   if(w < 0 || w >= Max_Waves) return 0;
   if(!g_waves[w].used) return 0;

   double range_strength     = CalcRangeStrength(w, atr_val, max_active_range);
   double adoption_freshness = CalcAdoptionFreshness(w, cur_bar_idx);
   double tier_state          = ScoreFromTier(g_waves[w].tier) * 100.0;
   double parent_status        = g_waves[w].is_parent ? 100.0 : 0.0;

   double total = range_strength*0.40 + adoption_freshness*0.30 +
                  tier_state*0.20 + parent_status*0.10;
   return MathMax(0.0, MathMin(100.0, total));
  }

// 互換用ラッパー: max_active_rangeを毎回再計算する版(単発呼び出し向け)
// ループ内で複数waveを評価する場合はCalcParentStrengthExを使い
// max_active_rangeを1回だけ計算して渡すこと(軽量化)
double CalcParentStrength(int w, double atr_val, int cur_bar_idx)
  {
   if(w < 0 || w >= Max_Waves) return 0;
   if(!g_waves[w].used) return 0;
   double max_active_range = CalcMaxActiveRange(g_waves[w].direction);
   return CalcParentStrengthEx(w, atr_val, cur_bar_idx, max_active_range);
  }

//+------------------------------------------------------------------+
// Dominant Wave Tracker（Layer10）
// 「市場が現在採用している波」= 同方向内でParent Strengthが最大のwave
// (最も大きい波ではない。これがTUTTO思想の核心)
//+------------------------------------------------------------------+
int FindDominantWave(int direction, double atr_val, int cur_bar_idx, double &out_strength)
  {
   double max_active_range = CalcMaxActiveRange(direction); // 1回だけ計算(軽量化)
   int best_w = -1;
   double best_score = -1;
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].direction != direction) continue;
      if(g_waves[w].stage != STAGE_S3A && g_waves[w].stage != STAGE_S3B) continue;
      double score = CalcParentStrengthEx(w, atr_val, cur_bar_idx, max_active_range);
      if(score > best_score) { best_score = score; best_w = w; }
     }
   out_strength = (best_w >= 0) ? best_score : 0.0;
   return best_w;
  }

//+------------------------------------------------------------------+
// Layer9: Market Geometry Acceptance Score（構造採用スコア）
// 「今のWaveが市場に採用されている度合い」を0〜100で数値化する
// BUY/SELLという方向性ラベルではなく、構造そのものの採用度を示す
//
// 40% Parent Strength（複合スコア、上記で算出済み）
// 20% TIER
// 20% Ghost Similarity（過去の同構造Waveの結果分布との一致）
// 20% HeatMap Density（その価格帯の構造発生密度）
//+------------------------------------------------------------------+
double CalcGeometryAcceptanceScoreEx(int w, double atr_val, int cur_bar_idx, double max_active_range)
  {
   if(w < 0 || w >= Max_Waves) return 0;
   if(!g_waves[w].used) return 0;

   int held = g_waves[w].structural_fib1_idx - g_waves[w].hl_candidate_idx;
   if(held < 0) held = 0;
   GhostStats gs = GetCachedGhostStats(w, held, g_waves[w].recorded_accel, g_waves[w].direction);

   double s_parent = CalcParentStrengthEx(w, atr_val, cur_bar_idx, max_active_range);
   double s_tier    = ScoreFromTier(g_waves[w].tier) * 100.0;
   double s_ghost   = ScoreFromGhost(gs) * 100.0;
   double s_heat    = ScoreFromHeat(g_waves[w].structural_fib1, 0) * 100.0;

   double total = s_parent*0.40 + s_tier*0.20 + s_ghost*0.20 + s_heat*0.20;
   return MathMax(0.0, MathMin(100.0, total));
  }

// 互換用ラッパー(単発呼び出し向け、max_active_rangeを内部で計算)
double CalcGeometryAcceptanceScore(int w, double atr_val, int cur_bar_idx)
  {
   if(w < 0 || w >= Max_Waves) return 0;
   if(!g_waves[w].used) return 0;
   double max_active_range = CalcMaxActiveRange(g_waves[w].direction);
   return CalcGeometryAcceptanceScoreEx(w, atr_val, cur_bar_idx, max_active_range);
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
// Object GC: 世代別削除（CRITICAL対応2: オブジェクト無限蓄積防止）
// 軌跡矢印(S1/HL/S3A/S3B)は永久保存せず、直近N世代のみ保持する
// ObjectsTotal()による全走査ではなく、世代番号ベースの名前マッチで
// 古い世代のプレフィックスのみを対象に削除する(軽量)
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// 指定generationが現在usedな(生存中の)waveに属しているか確認
// GC対象から保護するための生存チェック
//+------------------------------------------------------------------+
bool IsGenerationAlive(int g)
  {
   for(int w = 0; w < Max_Waves; w++)
     {
      if(g_waves[w].used && g_waves[w].generation == g) return true;
     }
   return false;
  }

input int Object_Count_Limit = 2000; // チャートオブジェクト数の上限(超過時は保持世代を圧縮)

void RunObjectGC()
  {
   // Object数上限チェック: 超過時は実質的な保持世代数を縮小してGCを積極化する
   // (理論・判定結果には影響しない。表示の保持期間のみを調整する)
   int effective_retention = Retention_Generations;
   int total_objs = ObjectsTotal(0, -1, -1);
   if(total_objs > Object_Count_Limit)
      effective_retention = MathMax(10, Retention_Generations / 2);

   if(g_generation_counter <= effective_retention) return; // GC不要
   int cutoff = g_generation_counter - effective_retention;

   // 直近のGC実行世代から、新たに古くなった世代分だけ削除する
   // (毎回0からcutoffまで全走査すると、長期運用で削除コストが
   //  線形に増加するため、最後にGCした地点を記憶して差分のみ処理)
   //
   // 重要: そのgenerationが現在も生存中のwaveに属している場合
   // GCを実行せずスキップする(進めない)。これにより
   // 「Wave本体は生きているのに軌跡矢印だけ消える」という
   // GC/LRU責任分離バグを防止する。生存中waveは将来KillWave/
   // KillWaveSilentでused=falseになった時点で次回GCの対象になる。
   int g = g_last_gc_generation;
   while(g < cutoff)
     {
      if(IsGenerationAlive(g))
        {
         break; // 生存中世代に到達したらここで停止(これより新しい世代は処理しない)
        }
      string prefixes[4];
      prefixes[0] = OBJ_PFX + "S1_G"  + IntegerToString(g) + "_";
      prefixes[1] = OBJ_PFX + "HL_G"  + IntegerToString(g) + "_";
      prefixes[2] = OBJ_PFX + "S3A_G" + IntegerToString(g) + "_";
      prefixes[3] = OBJ_PFX + "S3B_G" + IntegerToString(g) + "_";
      for(int p = 0; p < 4; p++)
         ObjectsDeleteAll(0, prefixes[p]);
      g++;
     }
   g_last_gc_generation = g;
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
      string tier_txt = (p.tier == TIER_ACTIVE) ? "ACTIVE" :
                        (p.tier == TIER_DORMANT) ? "DORMANT" : "STALE";
      string stage_txt = (p.wave_stage == STAGE_S3A) ? "S3A" : "S3B";
      string fb_txt     = p.is_fallback ? "[FB]" : "";
      color  line_clr   = (p.wave_stage == STAGE_S3A) ? clrLime : clrDodgerBlue;

      string txt = StringFormat("W%d %s%s SF1=%s",
                                p.wave_id, stage_txt, fb_txt,
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

//+------------------------------------------------------------------+
// ============== LAYER 8: VISUAL DECISION LAYER ==============
// 人間の判断を補助する最終UI。売買ロジックではない。
// 現在アクティブな構造をScore Engineの値で順位付けし
// 「どの構造が最も市場に採用されているか」を一覧表示する。
// 表示するのは順位・スコア・構造状態ラベルのみで、
// 発注やシグナル生成は一切行わない(本システムは分析専用)。
//+------------------------------------------------------------------+
input bool ShowDecisionLayer = true;
input int  Decision_TopN     = 5; // Active Child Waves表示の上限件数

struct DecisionRow
  {
   int    wave_idx;
   double score;
  };

//+------------------------------------------------------------------+
// MARKET GEOMETRY DASHBOARD（旧Visual Decision Layer全面再設計）
// 表示内容(確定仕様):
//   Dominant Parent Wave / Active Child Waves / Adoption Score /
//   TIER状態 / Ghost Similarity / Geometry Heat / Last Dead Parent /
//   Current Geometry State
// BUY/SELLという方向ラベルは表示しない。
// 「市場が現在採用している構造」を示すことが目的であり
// 売買方向の提示はTUTTO思想と矛盾するため意図的に排除する。
//+------------------------------------------------------------------+
void DrawVisualDecisionLayer(double atr_val, int cur_bar_idx)
  {
   string base = OBJ_PFX + "DECISION_";
   if(!ShowDecisionLayer) { ObjectsDeleteAll(0, base); return; }

   // Dominant Wave(方向ごとに1つ、Parent Strength最大)を検出
   double dom_strength_a = 0, dom_strength_b = 0;
   int dom_w_a = FindDominantWave(DIR_BUY,  atr_val, cur_bar_idx, dom_strength_a);
   int dom_w_b = FindDominantWave(DIR_SELL, atr_val, cur_bar_idx, dom_strength_b);
   int dom_w = (dom_strength_a >= dom_strength_b) ? dom_w_a : dom_w_b;
   double dom_strength = MathMax(dom_strength_a, dom_strength_b);

   // 軽量化: BUY/SELL各方向のmax_active_rangeを1回だけ計算しておく
   // (CalcMaxActiveRangeはMax_Wavesを全走査するため、ループ内で
   //  wave毎に呼ぶとO(MaxWaves^2)になってしまう)
   double max_range_buy  = CalcMaxActiveRange(DIR_BUY);
   double max_range_sell = CalcMaxActiveRange(DIR_SELL);

   // Active Child Waves: Dominant以外のS3A/S3B構造をAcceptance Score降順で列挙
   DecisionRow rows[];
   ArrayResize(rows, Max_Waves);
   int n = 0;
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].stage != STAGE_S3A && g_waves[w].stage != STAGE_S3B) continue;
      if(w == dom_w) continue; // Dominantは別枠表示のため除外
      double max_range = (g_waves[w].direction == DIR_BUY) ? max_range_buy : max_range_sell;
      rows[n].wave_idx = w;
      rows[n].score     = CalcGeometryAcceptanceScoreEx(w, atr_val, cur_bar_idx, max_range);
      n++;
     }
   for(int i = 0; i < n - 1; i++)
     {
      int best = i;
      for(int j = i+1; j < n; j++)
         if(rows[j].score > rows[best].score) best = j;
      if(best != i) { DecisionRow tmp = rows[i]; rows[i] = rows[best]; rows[best] = tmp; }
     }

   int shown = MathMin(n, Decision_TopN);
   int total_lines = 1 /*title*/ + 1 /*dominant*/ + 1 /*geometry state*/ +
                     1 /*last dead*/ + shown + 1 /*child header*/;
   int y_base = 10 + 16 * total_lines;

   string t = base + "TITLE";
   if(ObjectFind(0, t) < 0) ObjectCreate(0, t, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, t, OBJPROP_CORNER,    CORNER_LEFT_LOWER);
   ObjectSetInteger(0, t, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, t, OBJPROP_YDISTANCE, y_base);
   ObjectSetString (0, t, OBJPROP_TEXT,      "== MARKET GEOMETRY DASHBOARD (analysis only) ==");
   ObjectSetInteger(0, t, OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, t, OBJPROP_FONTSIZE,  10);
   ObjectSetString (0, t, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, t, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, t, OBJPROP_ANCHOR,    ANCHOR_LEFT_LOWER);
   y_base -= 16;

   // --- Dominant Parent Wave 行 ---
   string dn = base + "DOMINANT";
   if(ObjectFind(0, dn) < 0) ObjectCreate(0, dn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, dn, OBJPROP_CORNER,    CORNER_LEFT_LOWER);
   ObjectSetInteger(0, dn, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, dn, OBJPROP_YDISTANCE, y_base);
   if(dom_w >= 0)
     {
      int held = g_waves[dom_w].structural_fib1_idx - g_waves[dom_w].hl_candidate_idx;
      if(held < 0) held = 0;
      GhostStats gs = GetCachedGhostStats(dom_w, held, g_waves[dom_w].recorded_accel, g_waves[dom_w].direction);
      string tier_txt = (g_waves[dom_w].tier==TIER_ACTIVE)?"ACTIVE":
                        (g_waves[dom_w].tier==TIER_DORMANT)?"DORMANT":"STALE";
      string ghost_txt = gs.valid ? StringFormat("%.0f%%", gs.reach_TP1_rate*100) : "n/a";
      string txt = StringFormat("Dominant Parent: W%d  Adoption:%.0f  TIER:%s  Ghost:%s",
                                g_waves[dom_w].wave_id, dom_strength, tier_txt, ghost_txt);
      ObjectSetString(0, dn, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, dn, OBJPROP_COLOR, clrLime);
     }
   else
     {
      ObjectSetString(0, dn, OBJPROP_TEXT, "Dominant Parent: (none)");
      ObjectSetInteger(0, dn, OBJPROP_COLOR, clrGray);
     }
   ObjectSetInteger(0, dn, OBJPROP_FONTSIZE, 9);
   ObjectSetString (0, dn, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, dn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, dn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   y_base -= 16;

   // --- Current Geometry State 行 ---
   string gn = base + "GEOSTATE";
   if(ObjectFind(0, gn) < 0) ObjectCreate(0, gn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, gn, OBJPROP_CORNER,    CORNER_LEFT_LOWER);
   ObjectSetInteger(0, gn, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, gn, OBJPROP_YDISTANCE, y_base);
   string geo_state_txt = (dom_w < 0) ? "NO DOMINANT GEOMETRY" :
                          (dom_strength >= 70) ? "STRONG ADOPTION" :
                          (dom_strength >= 40) ? "PARTIAL ADOPTION" : "WEAK ADOPTION";
   ObjectSetString (0, gn, OBJPROP_TEXT, "Geometry State: " + geo_state_txt);
   ObjectSetInteger(0, gn, OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, gn, OBJPROP_FONTSIZE, 9);
   ObjectSetString (0, gn, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, gn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, gn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   y_base -= 16;

   // --- Last Dead Parent 行 ---
   string ln = base + "LASTDEAD";
   if(ObjectFind(0, ln) < 0) ObjectCreate(0, ln, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, ln, OBJPROP_CORNER,    CORNER_LEFT_LOWER);
   ObjectSetInteger(0, ln, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, ln, OBJPROP_YDISTANCE, y_base);
   string dead_txt = "Last Dead Parent: (none recorded)";
   if(g_last_dead[0].valid || g_last_dead[1].valid)
     {
      // 直近の2方向のうち、より新しい死亡情報を表示(簡易: 両方存在すれば両方表示)
      if(g_last_dead[0].valid && g_last_dead[1].valid)
         dead_txt = StringFormat("Last Dead Parent: range=%s / range=%s",
                                 DoubleToString(MathAbs(g_last_dead[0].structural_fib1-g_last_dead[0].fib0), _Digits),
                                 DoubleToString(MathAbs(g_last_dead[1].structural_fib1-g_last_dead[1].fib0), _Digits));
      else if(g_last_dead[0].valid)
         dead_txt = StringFormat("Last Dead Parent: range=%s",
                                 DoubleToString(MathAbs(g_last_dead[0].structural_fib1-g_last_dead[0].fib0), _Digits));
      else
         dead_txt = StringFormat("Last Dead Parent: range=%s",
                                 DoubleToString(MathAbs(g_last_dead[1].structural_fib1-g_last_dead[1].fib0), _Digits));
     }
   ObjectSetString (0, ln, OBJPROP_TEXT, dead_txt);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, ln, OBJPROP_FONTSIZE, 9);
   ObjectSetString (0, ln, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ln, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   y_base -= 16;

   // --- Active Child Waves ヘッダ ---
   string hn = base + "CHILDHDR";
   if(ObjectFind(0, hn) < 0) ObjectCreate(0, hn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, hn, OBJPROP_CORNER,    CORNER_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, hn, OBJPROP_YDISTANCE, y_base);
   ObjectSetString (0, hn, OBJPROP_TEXT,      "-- Active Child Waves --");
   ObjectSetInteger(0, hn, OBJPROP_COLOR,     clrDimGray);
   ObjectSetInteger(0, hn, OBJPROP_FONTSIZE,  9);
   ObjectSetString (0, hn, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, hn, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, hn, OBJPROP_ANCHOR,    ANCHOR_LEFT_LOWER);
   y_base -= 16;

   for(int i = 0; i < Decision_TopN; i++)
      SafeDelete(base + "ROW" + IntegerToString(i));

   for(int i = 0; i < shown; i++)
     {
      int w = rows[i].wave_idx;
      string tier_txt = (g_waves[w].tier==TIER_ACTIVE)?"ACTIVE":
                        (g_waves[w].tier==TIER_DORMANT)?"DORMANT":"STALE";
      string stage_txt = (g_waves[w].stage == STAGE_S3A) ? "S3A" : "S3B";
      color score_clr = (rows[i].score >= 70) ? clrLime :
                        (rows[i].score >= 40) ? clrYellow : clrGray;

      // 方向(BUY/SELL)は意図的に表示しない。構造の採用度のみを示す。
      string txt = StringFormat("W%d  %s  TIER:%s  Adoption:%.0f",
                                g_waves[w].wave_id, stage_txt, tier_txt, rows[i].score);

      string rn = base + "ROW" + IntegerToString(i);
      ObjectCreate(0, rn, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, rn, OBJPROP_CORNER,    CORNER_LEFT_LOWER);
      ObjectSetInteger(0, rn, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, rn, OBJPROP_YDISTANCE, y_base);
      ObjectSetString (0, rn, OBJPROP_TEXT,      txt);
      ObjectSetInteger(0, rn, OBJPROP_COLOR,     score_clr);
      ObjectSetInteger(0, rn, OBJPROP_FONTSIZE,  9);
      ObjectSetString (0, rn, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, rn, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, rn, OBJPROP_ANCHOR,    ANCHOR_LEFT_LOWER);
      y_base -= 16;
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
      g_waves[i].tier = TIER_ACTIVE;
      g_waves[i].last_update_bar = 0;
      g_waves[i].generation = 0;
      g_waves[i].ghost_cache_valid = false;
     }
   ArrayResize(g_active_packets, Max_Waves);
   for(int i = 0; i < Max_Waves; i++)
      g_active_packets[i] = MakeEmptyPacket();
   g_active_packet_count = 0;

   for(int i = 0; i < 2; i++) g_last_dead[i].valid = false;
   for(int i = 0; i < 2; i++) g_parent_dirty[i] = true; // 初回は必ずスキャンさせる

   g_generation_counter  = 0;
   g_last_gc_generation  = 0;

   ArrayResize(g_ghost_history, Ghost_History_Capacity);
   for(int i = 0; i < Ghost_History_Capacity; i++)
      g_ghost_history[i].valid = false;
   g_ghost_history_count = 0;
   g_ghost_history_head  = 0;
   g_ghost_history_version = 0;

   InitTFParams();
   g_last_bar = 0;
   g_heat_range_high = 0;
   g_heat_range_low  = 0;
   g_heat_last_recalc_bar = -1000000;
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

   //--- Object GC: 古い世代の軌跡矢印を削除(CRITICAL対応2)
   RunObjectGC();

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

   //================================================================
   // LAYER 5: HeatMap（価格帯ごとの構造発生密度）
   //================================================================
   RebuildHeatMap(high, low, rates_total);
   DrawHeatMap(time, rates_total);

   for(int idx = 0; idx < g_active_packet_count; idx++)
     {
      WavePacket p = g_active_packets[idx];
      if(p.wave_id == 0) continue;
      DrawAuthZoneLines(p);
     }

   //================================================================
   // LAYER 6: GhostWave（統計遷移場ラベル）
   //================================================================
   int last_confirmed = rates_total - 2;
   for(int w = 0; w < Max_Waves; w++)
      DrawGhostWaveLabel(w, time, last_confirmed);

   DrawWaveListPanel();
   DrawStatePanel(mkt_state, rci_val, vol_ok);

   //================================================================
   // LAYER 9+10: Market Geometry Acceptance Engine → Dashboard
   //================================================================
   DrawVisualDecisionLayer(g_atr_last, last_confirmed);

   UpdateDebugComment(rates_total, prev_calculated, cur_price);
   ChartRedraw(0);
   return rates_total;
  }