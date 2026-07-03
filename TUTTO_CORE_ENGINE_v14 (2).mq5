//+------------------------------------------------------------------+
//| TUTTO_CORE_ENGINE_v14.mq5                                       |
//| TUTTO CORE ARCHITECTURE v1.4 — 実戦トレード可視化版              |
//| Market Geometry Acceptance Engine 初期実装                      |
//| S1/HL/S3A/S3B/DEATH 矢印 + 右端Wave一覧パネル                  |
//| 新バー確定時のみ計算・過去バー再描画禁止                          |
//+------------------------------------------------------------------+
#property copyright   "TUTTO CORE ENGINE v1.4"
#property version     "1.50"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   0
// 矢印は全てObjectベースで描画（ステージ別5色のため
// プロットバッファでは色分けに限界があり、Object方式に統一）

//+------------------------------------------------------------------+
// INPUT
//+------------------------------------------------------------------+
input int    Fractal_Left       = 2;
input int    ATR_Period         = 14;
input double Revalidate_ATRx    = 2.0;
input int    Max_Waves          = 20;
input bool   ShowStructuralFib  = true;
input bool   ShowDynamicFib     = true;
input bool   ShowWaveList       = true;   // 右端Wave一覧表示
input double HL_Score_Threshold = 0.6;

//+------------------------------------------------------------------+
// 定数
//+------------------------------------------------------------------+
#define DIR_BUY    1
#define DIR_SELL  -1
#define STAGE_S1   0
#define STAGE_S3A  2
#define STAGE_S3B  3
#define STAGE_S4   4

double DummyBuf[]; // indicator_buffers=1 のダミー(未使用、プロット非表示)

//+------------------------------------------------------------------+
// HANDLES / グローバル
//+------------------------------------------------------------------+
int      hATR        = INVALID_HANDLE;
datetime g_last_bar   = 0;
int      g_next_id    = 1;
string   OBJ_PFX      = "TCE14_";
double   g_atr_last    = 0.0;

//+------------------------------------------------------------------+
// WAVE STRUCT
//+------------------------------------------------------------------+
struct TuttoWave
  {
   bool     used;
   int      stage;
   int      prev_stage;     // 前回バーでのstage（矢印重複描画防止）
   int      direction;

   double   fib0;
   int      fib0_idx;

   double   structural_fib1;
   int      structural_fib1_idx;

   double   dynamic_fib1;
   int      dynamic_fib1_idx;

   double   s3b_entry_value;
   int      s3b_entry_idx;

   int      impulse1_done;
   double   hl_candidate;
   int      hl_candidate_idx;
   int      hl_marker_drawn;  // HL確定マーカー描画済みフラグ

   int      impulse2_done;

   int      wave_id;

   // 描画オブジェクト名キャッシュ
   string   obj_sf;
   string   obj_df;
  };

TuttoWave g_waves[];

//+------------------------------------------------------------------+
// TFパラメータ
//+------------------------------------------------------------------+
int    g_required_bars     = 2;
double g_required_strength = 0.3;
int    g_s3b_max_wait      = 4;

void InitTFParams()
  {
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   if(tf >= PERIOD_H1)       { g_required_bars = 2; g_required_strength = 0.3; }
   else if(tf >= PERIOD_M15) { g_required_bars = 3; g_required_strength = 0.5; }
   else if(tf >= PERIOD_M5)  { g_required_bars = 5; g_required_strength = 0.7; }
   else                      { g_required_bars = 8; g_required_strength = 1.0; }
   g_s3b_max_wait = g_required_bars * 2;
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
   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO ENGINE v1.4 MGS");
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
// HL_SCORE（v1.4数式・変更なし）
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
// 矢印/マーカー描画ヘルパー（ステージ別固定色・1回限り）
// name は呼び出し側で一意性を保証する
//+------------------------------------------------------------------+
void DrawMarker(string name, datetime t, double price,
               color clr, int arrow_code, int width, int anchor)
  {
   if(ObjectFind(0, name) >= 0) return; // 既に存在＝再描画しない
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, t, price)) return;
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrow_code);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     width);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
// WAVE管理
//+------------------------------------------------------------------+
int AllocWave(int dir, double fib0v, int fib0i)
  {
   for(int i = 0; i < Max_Waves; i++)
     {
      if(g_waves[i].used) continue;
      g_waves[i].used                = true;
      g_waves[i].stage               = STAGE_S1;
      g_waves[i].prev_stage          = -1;
      g_waves[i].direction           = dir;
      g_waves[i].fib0                = fib0v;
      g_waves[i].fib0_idx            = fib0i;
      g_waves[i].structural_fib1     = fib0v;
      g_waves[i].structural_fib1_idx = fib0i;
      g_waves[i].dynamic_fib1        = fib0v;
      g_waves[i].dynamic_fib1_idx    = fib0i;
      g_waves[i].s3b_entry_value     = 0.0;
      g_waves[i].s3b_entry_idx       = -1;
      g_waves[i].impulse1_done       = 0;
      g_waves[i].hl_candidate        = 0.0;
      g_waves[i].hl_candidate_idx    = -1;
      g_waves[i].hl_marker_drawn     = 0;
      g_waves[i].impulse2_done       = 0;
      g_waves[i].wave_id             = g_next_id++;
      string b = OBJ_PFX + "W" + IntegerToString(g_waves[i].wave_id) + "_";
      g_waves[i].obj_sf = b + "SF";
      g_waves[i].obj_df = b + "DF";
      return i;
     }
   return -1;
  }

void KillWave(int w, datetime death_time, double death_price)
  {
   // 要件5: DEATH = 赤×表示
   string n = OBJ_PFX + "DEATH_" + IntegerToString(g_waves[w].wave_id);
   DrawMarker(n, death_time, death_price, clrRed, 251, 3,
             (g_waves[w].direction == DIR_BUY) ? ANCHOR_TOP : ANCHOR_BOTTOM);

   SafeDelete(g_waves[w].obj_sf);
   SafeDelete(g_waves[w].obj_df);
   g_waves[w].used  = false;
   g_waves[w].stage = STAGE_S4;
  }

//+------------------------------------------------------------------+
// STAGE1: Fib0生成 + 要件1(灰色▲)描画
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
            // 要件1: S1発見時 灰色▲
            string n = OBJ_PFX + "S1_" + IntegerToString(g_waves[slot].wave_id);
            DrawMarker(n, time[check], low[check], clrGray, 233, 1, ANCHOR_TOP);
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
            DrawMarker(n, time[check], high[check], clrGray, 234, 1, ANCHOR_BOTTOM);
           }
        }
     }
  }

//+------------------------------------------------------------------+
// Impulse1: HL候補確定 + 要件2(黄色▲)描画
//+------------------------------------------------------------------+
void UpdateImpulse1(int w, const double &high[], const double &low[],
                    const datetime &time[], int bar_idx, int total, int fl)
  {
   if(g_waves[w].impulse1_done) return;

   int check = bar_idx - fl;
   if(check <= g_waves[w].fib0_idx) return;
   if(check >= total) return;

   int dir = g_waves[w].direction;
   if(dir == DIR_BUY)
     {
      if(IsFractalLow(low, check, total, fl) && low[check] > g_waves[w].fib0)
        {
         g_waves[w].hl_candidate     = low[check];
         g_waves[w].hl_candidate_idx = check;
         g_waves[w].impulse1_done    = 1;

         if(!g_waves[w].hl_marker_drawn)
           {
            // 要件2: HL確定時 黄色▲
            string n = OBJ_PFX + "HL_" + IntegerToString(g_waves[w].wave_id);
            DrawMarker(n, time[check], low[check], clrYellow, 233, 2, ANCHOR_TOP);
            g_waves[w].hl_marker_drawn = 1;
           }
        }
     }
   else
     {
      if(IsFractalHigh(high, check, total, fl) && high[check] < g_waves[w].fib0)
        {
         g_waves[w].hl_candidate     = high[check];
         g_waves[w].hl_candidate_idx = check;
         g_waves[w].impulse1_done    = 1;

         if(!g_waves[w].hl_marker_drawn)
           {
            string n = OBJ_PFX + "HL_" + IntegerToString(g_waves[w].wave_id);
            DrawMarker(n, time[check], high[check], clrYellow, 234, 2, ANCHOR_BOTTOM);
            g_waves[w].hl_marker_drawn = 1;
           }
        }
     }
  }

//+------------------------------------------------------------------+
// Impulse2: STAGE2判定 → S3A移行 + 要件3(緑▲)描画
//+------------------------------------------------------------------+
bool UpdateImpulse2(int w, const double &high[], const double &low[],
                    const double &close[], const datetime &time[],
                    int bar_idx, int total, int fl, double atr_val)
  {
   if(!g_waves[w].impulse1_done) return false;

   int check = bar_idx - fl;
   if(check <= g_waves[w].hl_candidate_idx) return false;
   if(check >= total) return false;

   int dir = g_waves[w].direction;
   double hh_val = 0;
   int    hh_idx = -1;

   if(dir == DIR_BUY)
     {
      if(IsFractalHigh(high, check, total, fl) && high[check] > g_waves[w].hl_candidate)
        { hh_val = high[check]; hh_idx = check; }
     }
   else
     {
      if(IsFractalLow(low, check, total, fl) && low[check] < g_waves[w].hl_candidate)
        { hh_val = low[check]; hh_idx = check; }
     }

   if(hh_idx < 0) return false;

   int    held  = hh_idx - g_waves[w].hl_candidate_idx;
   double dur   = CalcDurationScore(held);
   double dep   = CalcDepthScore(g_waves[w].fib0, hh_val, g_waves[w].hl_candidate, dir);
   double acc   = CalcAccelScore(close[hh_idx], g_waves[w].hl_candidate, atr_val);
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

   bool stage2_ok = fib0_ok && !hl_broken &&
                    (score >= HL_Score_Threshold) &&
                    (acc   >= g_required_strength);

   if(stage2_ok)
     {
      bool mono = (dir == DIR_BUY)
                  ? (hh_val > g_waves[w].structural_fib1)
                  : (hh_val < g_waves[w].structural_fib1);

      if(g_waves[w].stage == STAGE_S1 || g_waves[w].stage == STAGE_S3B || mono)
        {
         g_waves[w].structural_fib1     = hh_val;
         g_waves[w].structural_fib1_idx = hh_idx;
         g_waves[w].dynamic_fib1        = hh_val;
         g_waves[w].dynamic_fib1_idx    = hh_idx;
         g_waves[w].impulse2_done       = 1;
         g_waves[w].stage               = STAGE_S3A;

         // 要件3: S3A認証時 緑▲（1回のみ、wave_id単位で一意）
         string n = OBJ_PFX + "S3A_" + IntegerToString(g_waves[w].wave_id)
                    + "_" + IntegerToString(hh_idx);
         DrawMarker(n, time[hh_idx], hh_val, clrLime, dir==DIR_BUY?233:234, 3,
                   dir==DIR_BUY?ANCHOR_TOP:ANCHOR_BOTTOM);
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
   if(g_waves[w].stage != STAGE_S3A) return;

   int check = bar_idx - fl;
   if(check <= g_waves[w].dynamic_fib1_idx) return;
   if(check >= total) return;

   int dir = g_waves[w].direction;
   if(dir == DIR_BUY)
     {
      if(IsFractalHigh(high, check, total, fl) && high[check] > g_waves[w].dynamic_fib1)
        { g_waves[w].dynamic_fib1 = high[check]; g_waves[w].dynamic_fib1_idx = check; }
     }
   else
     {
      if(IsFractalLow(low, check, total, fl) && low[check] < g_waves[w].dynamic_fib1)
        { g_waves[w].dynamic_fib1 = low[check]; g_waves[w].dynamic_fib1_idx = check; }
     }
  }

//+------------------------------------------------------------------+
// 状態遷移（DEATH-1最優先） + 要件4(青▲ S3B進入)・要件5(赤× DEATH)
//+------------------------------------------------------------------+
void EvaluateTransitions(int w, double cur_close, datetime cur_time,
                         int bar_idx, double atr_val)
  {
   if(!g_waves[w].used) return;
   int dir = g_waves[w].direction;

   bool dead = false;
   if(g_waves[w].stage == STAGE_S3A)
      dead = (dir == DIR_BUY) ? (cur_close < g_waves[w].structural_fib1)
                               : (cur_close > g_waves[w].structural_fib1);
   else if(g_waves[w].stage == STAGE_S3B)
      dead = (dir == DIR_BUY) ? (cur_close < g_waves[w].s3b_entry_value)
                               : (cur_close > g_waves[w].s3b_entry_value);

   if(dead)
     {
      KillWave(w, cur_time, cur_close); // 要件5
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

         // 要件4: S3B進入時 青▲（1回のみ）
         string n = OBJ_PFX + "S3B_" + IntegerToString(g_waves[w].wave_id)
                    + "_" + IntegerToString(bar_idx);
         DrawMarker(n, cur_time, cur_close, clrDodgerBlue, dir==DIR_BUY?233:234, 2,
                   dir==DIR_BUY?ANCHOR_TOP:ANCHOR_BOTTOM);
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
// Fib1ライン描画（既存・変更なし）
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
// 要件10: 右端 Wave一覧パネル
// 「現在市場がどのWaveを採用しているか」を一目で把握
//+------------------------------------------------------------------+
void DrawWaveListPanel()
  {
   if(!ShowWaveList)
     {
      ObjectsDeleteAll(0, OBJ_PFX + "PANEL_");
      return;
     }

   string base = OBJ_PFX + "PANEL_";

   // タイトル
   string t = base + "TITLE";
   if(ObjectFind(0, t) < 0) ObjectCreate(0, t, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, t, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, t, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, t, OBJPROP_YDISTANCE, 10);
   ObjectSetString (0, t, OBJPROP_TEXT,      "== ACTIVE WAVES (MGS) ==");
   ObjectSetInteger(0, t, OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, t, OBJPROP_FONTSIZE,  10);
   ObjectSetString (0, t, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, t, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, t, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);

   // 既存の行ラベルを全削除してから再構築（行数が変動するため）
   for(int i = 0; i < Max_Waves; i++)
      SafeDelete(base + "ROW" + IntegerToString(i));

   int y = 28;
   int row = 0;
   for(int w = 0; w < Max_Waves; w++)
     {
      if(!g_waves[w].used) continue;
      if(g_waves[w].stage != STAGE_S3A && g_waves[w].stage != STAGE_S3B) continue;

      string dir_txt   = (g_waves[w].direction == DIR_BUY) ? "BUY" : "SELL";
      string stage_txt = (g_waves[w].stage == STAGE_S3A) ? "S3A" : "S3B";
      color  line_clr  = (g_waves[w].stage == STAGE_S3A) ? clrLime : clrDodgerBlue;
      if(g_waves[w].direction == DIR_SELL && g_waves[w].stage == STAGE_S3A)
         line_clr = clrOrangeRed;

      string txt = StringFormat("W%d  %s %s  SF1=%s",
                                g_waves[w].wave_id, dir_txt, stage_txt,
                                DoubleToString(g_waves[w].structural_fib1, _Digits));

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

      y += 16;
      row++;
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
// デバッグComment
//+------------------------------------------------------------------+
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
      "TUTTO ENGINE v1.4 MGS\n",
      "Bars=", rates_total, " prev=", prev_calculated, "\n",
      "ATR=", DoubleToString(g_atr_last, _Digits), "\n",
      "S1=", s1, " S3A=", s3a, " S3B=", s3b, "\n",
      "TotalWaveID=", g_next_id - 1
   );
  }

//+------------------------------------------------------------------+
// OnCalculate
// 要件6,7,8: 新バー確定時のみ計算・最新バーのみ監視・過去再描画禁止
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
      Comment("TUTTO v1.4 waiting... (", rates_total, "/", min_req, ")");
      return 0;
     }

   //--- ティック時はATR1本だけ取得してCommentのみ更新（要件6: 軽量リアルタイム監視）
   double atr_tmp[1];
   if(CopyBuffer(hATR, 0, 1, 1, atr_tmp) > 0)
      g_atr_last = atr_tmp[0];

   datetime cur_bar_time = time[rates_total - 2];
   bool new_bar = (cur_bar_time != g_last_bar);

   if(!new_bar)
     {
      // 要件7,9: 同一バー内ティックでは何も再描画しない
      UpdateComment(rates_total, prev_calculated);
      return prev_calculated;
     }

   //--- 要件8: 新バー確定時のみ以下を実行
   g_last_bar = cur_bar_time;

   if(g_atr_last <= 0.0)
     {
      UpdateComment(rates_total, prev_calculated);
      return prev_calculated;
     }

   //--- 処理範囲: 要件6「最新バーのみ監視」
   // prev_calculatedが有効なら直前確定分のみ、初回のみ全履歴
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

   for(int i = start; i <= rates_total - 2; i++)
     {
      int atr_pos = rates_total - 1 - i;
      if(atr_pos < 0 || atr_pos >= got) continue;
      double atr_val = atr_buf[atr_pos];
      if(atr_val <= 0.0) continue;

      //--- STAGE1探索 + 灰色▲
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

   //--- Fib1ライン更新（現在アクティブなwaveのみ、過去バーへの再描画はしない）
   for(int w = 0; w < Max_Waves; w++)
      DrawFibLines(w);

   //--- 要件10: 右端Wave一覧パネル
   DrawWaveListPanel();

   UpdateComment(rates_total, prev_calculated);
   ChartRedraw(0);
   return rates_total;
  }