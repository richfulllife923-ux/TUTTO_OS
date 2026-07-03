//+------------------------------------------------------------------+
//|  TUTTO MASTER OS v3.1-debug                                      |
//|  AUTH完全監査ログ版                                              |
//|  目的: CAuth::Analyze()の実挙動をMT5ログで確定する              |
//+------------------------------------------------------------------+
#property copyright "TUTTO MSE v3.1-debug"
#property version   "3.11"
#property indicator_chart_window
#property indicator_plots 0

//+------------------------------------------------------------------+
//  ENUM
//+------------------------------------------------------------------+
enum TUTTO_PHASE
  {
   PHASE_EXHAUSTION     = 0,
   PHASE_AUTHENTICATION = 1,
   PHASE_DISTRIBUTION   = 2,
   PHASE_RELEASE        = 3,
   PHASE_EXPANSION      = 4,
   PHASE_COMPRESSION    = 5
  };

enum SWEEP_DIR
  {
   SWEEP_NONE = 0,
   SWEEP_UP   = 1,
   SWEEP_DOWN = 2
  };

enum AUTH_VERDICT
  {
   AUTH_REAL    = 0,
   AUTH_FAKE    = 1,
   AUTH_PENDING = 2
  };

enum RELEASE_DIR
  {
   RELEASE_UP      = 0,
   RELEASE_DOWN    = 1,
   RELEASE_UNKNOWN = 2
  };

enum SWING_PATTERN
  {
   PATTERN_NONE        = 0,
   PATTERN_LOW_TO_HIGH = 1,
   PATTERN_HIGH_TO_LOW = 2
  };

//+------------------------------------------------------------------+
//  STRUCT
//+------------------------------------------------------------------+
struct CompressionState
  {
   double   score;
   bool     is_compressed;
   double   atr_ratio;
   double   bb_ratio;
   double   range_ratio;
   datetime last_update;
  };

struct SweepState
  {
   bool      detected;
   SWEEP_DIR direction;
   double    sweep_price;
   int       bars_since;
   double    wick_ratio;
   double    volume_spike;
   bool      confirmed;
   datetime  timestamp;
  };

struct AuthZoneData
  {
   double       zone_low;
   double       zone_high;
   double       avg_velocity;
   double       auth_score;
   int          bars_inside;
   int          rejection_count;
   AUTH_VERDICT verdict;
  };

struct EnergySnapshot
  {
   double      compression_pct;
   double      release_prob;
   double      release_quality;
   RELEASE_DIR release_dir;
   TUTTO_PHASE phase;
   TUTTO_PHASE prev_phase;
   string      local_dir;
   string      macro_dir;
   string      dir_warning;
   double      conflict_score;
   double      liquidity_gravity_near;
   datetime    snapshot_time;
   double      rel_compression;
   double      rel_structure;
   double      rel_sweep;
   double      rel_divergence;
   double      rel_volume;
   double      rel_mtf;
   string      divergence_label;
  };

struct SwingPoints
  {
   double        swing_high;
   double        swing_low;
   int           sh_bar_index;
   int           sl_bar_index;
   datetime      sh_time;
   datetime      sl_time;
   double        range;
   bool          is_valid;
   SWING_PATTERN pattern;
  };

struct SignalState
  {
   bool     active;
   bool     pending;
   int      pending_direction;
   datetime signal_bar_time;
   int      direction;
   double   entry_price;
   double   tp1;
   double   tp2;
   double   tp3;
   double   sl;
   double   structure_break_level;
   datetime entry_time;
   bool     tp1_hit;
   bool     tp2_hit;
   bool     tp3_hit;
   bool     sl_hit;
   bool     trade_finished;
   double   rr1;
   double   rr2;
   double   rr3;
   double   swing_high_used;
   double   swing_low_used;
   bool     structure_warning;
   bool     structure_broken;
   int      warning_count;
   bool     auth_alerted;
   bool     rel_alerted;
   bool     rq_alerted;
   bool     warn_broken_alerted;
   // --- SETUP (SWEEP不要・AUTH+RELのみ) ---
   bool     buy_setup;
   bool     sell_setup;
   int      setup_count_buy;
   int      setup_count_sell;
  };

//+------------------------------------------------------------------+
//  定数
//+------------------------------------------------------------------+
#define ATR_PERIOD     14
#define ATR_BASE       50
#define BB_PERIOD      20
#define COMP_TRIG      65.0
#define WICK_MIN       0.60
#define VOL_MIN        1.20   // v3.1: 1.50→1.20 (BTC M1 感度改善)
#define SW_LOOK        20
#define SW_CONF        2
#define AUTH_IL        2.330
#define AUTH_IH        2.618
#define AUTH_TL        3.770
#define AUTH_TH        4.236
#define RQ_FAKE        40.0
#define RQ_REAL        70.0
#define MTF_SEC        30
#define PHASE_HIST_MAX 8
#define SWING_SEARCH   100
#define ATR_SWING_MULT 1.5
#define RQ_WARN_LOW    50.0
#define DASH_PFX       "TUTTOD_"
#define SIG_PFX        "TUTTOSIG_"

//+------------------------------------------------------------------+
//  グローバル変数
//+------------------------------------------------------------------+
TUTTO_PHASE  g_phase_history[PHASE_HIST_MAX];
datetime     g_phase_times[PHASE_HIST_MAX];
int          g_phase_hist_count = 0;
TUTTO_PHASE  g_last_phase       = PHASE_COMPRESSION;
AUTH_VERDICT g_prev_auth        = AUTH_PENDING;
RELEASE_DIR  g_prev_rel         = RELEASE_UNKNOWN;
double       g_prev_rq          = 0.0;
SignalState  g_signal;
SwingPoints  g_swing;

// --- デバッグカウンター ---
int g_detect_count_buy  = 0;
int g_detect_count_sell = 0;

//+------------------------------------------------------------------+
//  前方宣言
//+------------------------------------------------------------------+
void   InitSignalState(SignalState &s);
void   InitSwingPoints(SwingPoints &sp);
bool   CalcSwingPoints(SwingPoints &sp, int direction,
                       int rates_total, double atr14_val);
void   CalcTPSL(SwingPoints &sp, SignalState &sig);
void   DeleteSignalObjects();
void   DrawEntryObjects(SignalState &sig);
void   DrawRR(SignalState &sig);
void   DrawHLineSig(string name, double price, color clr,
                    int style, string tooltip);
void   DrawTextSig(string name, double price,
                   string txt, color clr);
void   FireSignalAlert(string event_type, SignalState &sig);
void   FireStructureAlert(string alert_type, string level,
                          SignalState &sig);
void   DetectBuySell(EnergySnapshot &es, SweepState &ss,
                     AuthZoneData &auth, SignalState &sig,
                     int rates_total);
void   DetectSetup(EnergySnapshot &es, AuthZoneData &auth,
                   SignalState &sig);
void   MonitorTPSL(SignalState &sig);
void   MonitorAuth(SignalState &sig, AuthZoneData &auth,
                   AUTH_VERDICT prev_a);
void   MonitorREL(SignalState &sig, EnergySnapshot &es,
                  RELEASE_DIR prev_r);
void   MonitorRQ(SignalState &sig, EnergySnapshot &es,
                 double prev_q);
void   MonitorStructure(SignalState &sig, AuthZoneData &auth,
                        EnergySnapshot &es);
void   CheckPhaseTransition(TUTTO_PHASE new_phase,
                             EnergySnapshot &es);
string PhaseStr(TUTTO_PHASE p);

//+------------------------------------------------------------------+
//  CMTFManager
//+------------------------------------------------------------------+
class CMTFManager
  {
private:
   int    m_h4ma, m_d1ma, m_h4em;
   double m_h4ma_v, m_d1ma_v, m_h4em_v;
   bool   m_h4bull, m_d1bull;
public:
   bool Init()
     {
      m_h4ma  = iMA(_Symbol,PERIOD_H4,200,0,MODE_SMA,PRICE_CLOSE);
      m_d1ma  = iMA(_Symbol,PERIOD_D1,200,0,MODE_SMA,PRICE_CLOSE);
      m_h4em  = iMA(_Symbol,PERIOD_H4, 50,0,MODE_EMA,PRICE_CLOSE);
      if(m_h4ma==INVALID_HANDLE||m_d1ma==INVALID_HANDLE||
         m_h4em==INVALID_HANDLE) return false;
      m_h4ma_v=0; m_d1ma_v=0; m_h4em_v=0;
      m_h4bull=false; m_d1bull=false;
      return true;
     }
   void Update()
     {
      double b[]; ArraySetAsSeries(b,true);
      if(CopyBuffer(m_h4ma,0,0,1,b)>0) m_h4ma_v=b[0];
      if(CopyBuffer(m_d1ma,0,0,1,b)>0) m_d1ma_v=b[0];
      if(CopyBuffer(m_h4em,0,0,1,b)>0) m_h4em_v=b[0];
      double h4c[]; ArraySetAsSeries(h4c,true);
      if(CopyClose(_Symbol,PERIOD_H4,0,3,h4c)>0)
         m_h4bull=(h4c[0]>m_h4ma_v);
      double d1c[]; ArraySetAsSeries(d1c,true);
      if(CopyClose(_Symbol,PERIOD_D1,0,3,d1c)>0)
         m_d1bull=(d1c[0]>m_d1ma_v);
     }
   bool   IsH4Bull() { return m_h4bull; }
   bool   IsD1Bull() { return m_d1bull; }
   double GetH4MA()  { return m_h4ma_v; }
   double GetD1MA()  { return m_d1ma_v; }
   void Deinit()
     {
      IndicatorRelease(m_h4ma);
      IndicatorRelease(m_d1ma);
      IndicatorRelease(m_h4em);
     }
  };

//+------------------------------------------------------------------+
//  CCompression
//+------------------------------------------------------------------+
class CCompression
  {
private:
   int              m_atr, m_bb;
   CompressionState m_cs;
   datetime         m_ct;
public:
   int GetATRHandle() { return m_atr; }
   bool Init()
     {
      m_atr=iATR(_Symbol,PERIOD_CURRENT,ATR_PERIOD);
      m_bb =iBands(_Symbol,PERIOD_CURRENT,BB_PERIOD,0,2,PRICE_CLOSE);
      if(m_atr==INVALID_HANDLE||m_bb==INVALID_HANDLE) return false;
      m_cs.score=0; m_cs.is_compressed=false; m_ct=0;
      return true;
     }
   CompressionState Calc(bool nb)
     {
      if(!nb&&m_ct>0) return m_cs;
      double ab[]; ArraySetAsSeries(ab,true);
      if(CopyBuffer(m_atr,0,0,ATR_BASE+1,ab)<ATR_BASE+1) return m_cs;
      double an=ab[0],abase=0;
      for(int i=1;i<=ATR_BASE;i++) abase+=ab[i];
      abase/=ATR_BASE;
      m_cs.atr_ratio=(abase>0)?an/abase:1.0;
      double as=MathMax(0.0,(1.0-m_cs.atr_ratio)/0.35)*40.0;
      double bu[],bl[];
      ArraySetAsSeries(bu,true); ArraySetAsSeries(bl,true);
      if(CopyBuffer(m_bb,1,0,21,bu)<21) return m_cs;
      if(CopyBuffer(m_bb,2,0,21,bl)<21) return m_cs;
      double bn=bu[0]-bl[0],bbase=0;
      for(int i=1;i<=20;i++) bbase+=(bu[i]-bl[i]);
      bbase/=20;
      m_cs.bb_ratio=(bbase>0)?bn/bbase:1.0;
      double bs=MathMax(0.0,(1.0-m_cs.bb_ratio)/0.20)*30.0;
      double hi[],lo[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      if(CopyHigh(_Symbol,PERIOD_CURRENT,0,51,hi)<51) return m_cs;
      if(CopyLow (_Symbol,PERIOD_CURRENT,0,51,lo)<51) return m_cs;
      double rn=0,rb=0;
      for(int i=0;i<10;i++) rn+=(hi[i]-lo[i]);
      for(int i=0;i<50;i++) rb+=(hi[i]-lo[i]);
      m_cs.range_ratio=(rb>0)?(rn/10.0)/(rb/50.0):1.0;
      double rs=MathMax(0.0,(1.0-m_cs.range_ratio)/0.40)*30.0;
      m_cs.score=MathMin(as+bs+rs,100.0);
      m_cs.is_compressed=(m_cs.score>COMP_TRIG);
      m_cs.last_update=TimeCurrent();
      m_ct=TimeCurrent();
      return m_cs;
     }
   void Deinit()
     {
      IndicatorRelease(m_atr);
      IndicatorRelease(m_bb);
     }
  };

//+------------------------------------------------------------------+
//  CSweep
//+------------------------------------------------------------------+
class CSweep
  {
private:
   int        m_vm;
   SweepState m_sc;
public:
   bool Init()
     {
      m_vm=iMA(_Symbol,PERIOD_CURRENT,20,0,MODE_SMA,VOLUME_TICK);
      if(m_vm==INVALID_HANDLE) return false;
      m_sc.detected=false; m_sc.direction=SWEEP_NONE;
      return true;
     }
   SweepState Detect(bool nb)
     {
      if(!nb)
        {
         if(!m_sc.detected) m_sc.direction=SWEEP_NONE;
         return m_sc;
        }
      double hi[],lo[],op[],cl[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      ArraySetAsSeries(op,true); ArraySetAsSeries(cl,true);
      if(CopyHigh (_Symbol,PERIOD_CURRENT,0,30,hi)<30) return m_sc;
      if(CopyLow  (_Symbol,PERIOD_CURRENT,0,30,lo)<30) return m_sc;
      if(CopyOpen (_Symbol,PERIOD_CURRENT,0,30,op)<30) return m_sc;
      if(CopyClose(_Symbol,PERIOD_CURRENT,0,30,cl)<30) return m_sc;
      double vm[]; ArraySetAsSeries(vm,true);
      if(CopyBuffer(m_vm,0,0,30,vm)<30) return m_sc;
      long vr[];
      if(CopyTickVolume(_Symbol,PERIOD_CURRENT,0,30,vr)<30) return m_sc;
      m_sc.detected=false; m_sc.direction=SWEEP_NONE;
      for(int i=1;i<=5;i++)
        {
         double ph=hi[i+1],pl=lo[i+1];
         for(int j=i+2;j<=i+SW_LOOK&&j<30;j++)
           { ph=MathMax(ph,hi[j]); pl=MathMin(pl,lo[j]); }
         double rng=hi[i]-lo[i];
         if(rng<_Point) continue;
         double vrat=(vm[i]>0)?(double)vr[i]/vm[i]:0;
         double body=MathAbs(op[i]-cl[i]);
         double body_ratio=(rng>0)?body/rng:1.0;
         double wu=hi[i]-MathMax(op[i],cl[i]);
         double wru=wu/rng;
         if(hi[i]>ph&&wru>WICK_MIN&&vrat>VOL_MIN&&
            cl[i]<ph&&body_ratio<0.50)   // v3.1: 0.35→0.50
           {
            m_sc.detected=true; m_sc.direction=SWEEP_UP;
            m_sc.sweep_price=hi[i]; m_sc.bars_since=i;
            m_sc.wick_ratio=wru; m_sc.volume_spike=vrat;
            m_sc.confirmed=(i>=SW_CONF);
            m_sc.timestamp=iTime(_Symbol,PERIOD_CURRENT,i);
            return m_sc;
           }
         double wd=MathMin(op[i],cl[i])-lo[i];
         double wrd=wd/rng;
         if(lo[i]<pl&&wrd>WICK_MIN&&vrat>VOL_MIN&&
            cl[i]>pl&&body_ratio<0.50)   // v3.1: 0.35→0.50
           {
            m_sc.detected=true; m_sc.direction=SWEEP_DOWN;
            m_sc.sweep_price=lo[i]; m_sc.bars_since=i;
            m_sc.wick_ratio=wrd; m_sc.volume_spike=vrat;
            m_sc.confirmed=(i>=SW_CONF);
            m_sc.timestamp=iTime(_Symbol,PERIOD_CURRENT,i);
            return m_sc;
           }
        }
      return m_sc;
     }
   void Deinit() { IndicatorRelease(m_vm); }
  };

//+------------------------------------------------------------------+
//  CPhase
//+------------------------------------------------------------------+
class CPhase
  {
private:
   int m_atr;
   bool IsExpansion()
     {
      double ab[]; ArraySetAsSeries(ab,true);
      if(CopyBuffer(m_atr,0,0,51,ab)<51) return false;
      double an=ab[0],abase=0;
      for(int i=1;i<=50;i++) abase+=ab[i];
      abase/=50;
      return(an>abase*1.5);
     }
   bool InZone(double p,double ah,double al,double ll,double lh)
     {
      if(ah<=al) return false;
      double r=ah-al;
      return(p>=al+ll*r&&p<=al+lh*r);
     }
public:
   bool Init()
     {
      m_atr=iATR(_Symbol,PERIOD_CURRENT,14);
      return(m_atr!=INVALID_HANDLE);
     }
   TUTTO_PHASE Det(CompressionState &cs,SweepState &ss,CMTFManager &mtf)
     {
      double p=iClose(_Symbol,PERIOD_CURRENT,0);
      double h20=0,l20=DBL_MAX;
      for(int i=1;i<=20;i++)
        {
         h20=MathMax(h20,iHigh(_Symbol,PERIOD_CURRENT,i));
         l20=MathMin(l20,iLow (_Symbol,PERIOD_CURRENT,i));
        }
      if(IsExpansion()&&cs.score<30)         return PHASE_EXHAUSTION;
      if(InZone(p,h20,l20,AUTH_IL,AUTH_IH)||
         InZone(p,h20,l20,AUTH_TL,AUTH_TH)) return PHASE_AUTHENTICATION;
      if(InZone(p,h20,l20,AUTH_TL,AUTH_TH)&&
         !IsExpansion())                     return PHASE_DISTRIBUTION;
      if(ss.confirmed&&!cs.is_compressed)    return PHASE_RELEASE;
      if(IsExpansion())                      return PHASE_EXPANSION;
      return PHASE_COMPRESSION;
     }
   void Deinit() { IndicatorRelease(m_atr); }
  };

//+------------------------------------------------------------------+
//  CAuth v3.2 — Zone Interaction Layer
//  設計確定版: ステートレス / MA排除 / 帯幅正規化 / HARD GATE
//  static変数ゼロ / 外部依存: ATRハンドルのみ
//  互換: AuthZoneData構造体 / Analyze(price,ah,al)シグネチャ維持
//+------------------------------------------------------------------+
class CAuth
  {
private:
   int m_atr_handle;

   //----------------------------------------------------------------
   // LAYER4ヘルパー: Zone Rejection Wick
   // 直近3本スキャン（i=1,2,3 確定済みバーのみ・リペイントなし）
   // 上方拒絶: high > zh && close < zh → wick_len = high - zh
   // 下方拒絶: low  < zl && close > zl → wick_len = zl  - low
   // 最大値を返却（価格単位）
   //----------------------------------------------------------------
   double CalcZoneWick(double zl, double zh)
     {
      double max_wick = 0.0;
      for(int i = 1; i <= 3; i++)
        {
         double hi = iHigh (_Symbol, PERIOD_CURRENT, i);
         double lo = iLow  (_Symbol, PERIOD_CURRENT, i);
         double cl = iClose(_Symbol, PERIOD_CURRENT, i);

         // 上方拒絶: 高値がzhを突き抜け、終値がzh未満に戻った
         if(hi > zh && cl < zh)
           {
            double wick_up = hi - zh;
            if(wick_up > max_wick) max_wick = wick_up;
           }

         // 下方拒絶: 安値がzlを突き抜け、終値がzlを上回って戻った
         if(lo < zl && cl > zl)
           {
            double wick_dn = zl - lo;
            if(wick_dn > max_wick) max_wick = wick_dn;
           }
        }
      return max_wick;  // 価格単位の最大拒絶ヒゲ長
     }

   //----------------------------------------------------------------
   // LAYER5ヘルパー: 連続帯内本数（Continuity）
   // 現在バー(i=0)から遡り、Closeがzl〜zh内である
   // 連続本数をカウント（帯外になった時点で停止）
   // i=0: 現在足（未確定）を含む → 注意: 未来参照ではない
   // i=0のCloseは現在のBidに近似。nbのみで呼ばれる設計のため許容
   //----------------------------------------------------------------
   int CalcContinuityBars(double zl, double zh)
     {
      int count = 0;
      for(int i = 0; i <= 49; i++)
        {
         double cl = iClose(_Symbol, PERIOD_CURRENT, i);
         if(cl >= zl && cl <= zh)
            count++;
         else
            break;  // 帯外になった時点で即停止（連続カウント）
        }
      return count;
     }

public:
   bool Init()
     {
      m_atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_PERIOD);
      return (m_atr_handle != INVALID_HANDLE);
     }

   void Deinit()
     {
      if(m_atr_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr_handle);
     }

   AuthZoneData Analyze(double price, double ah, double al)
     {
      // 構造体初期化
      AuthZoneData az;
      az.zone_low       = 0.0;
      az.zone_high      = 0.0;
      az.bars_inside    = 0;
      az.avg_velocity   = 0.0;
      az.rejection_count= 0;
      az.auth_score     = 0.0;
      az.verdict        = AUTH_FAKE;  // デフォルトFAKE（安全側）

      // ガード: 無効入力
      if(ah <= al || al <= 0.0) return az;

      //============================================================
      // ゾーン計算（TUTTO原典 Fib係数変更禁止）
      // AUTH_IL=2.330 AUTH_IH=2.618 AUTH_TL=3.770 AUTH_TH=4.236
      //============================================================
      double r  = ah - al;
      double zl = al + AUTH_IL * r;
      double zh = al + AUTH_IH * r;
      // 終末帯切替: priceが終末帯下限に到達している場合
      if(price >= al + AUTH_TL * r)
        {
         zl = al + AUTH_TL * r;
         zh = al + AUTH_TH * r;
        }
      az.zone_low  = zl;
      az.zone_high = zh;

      // 帯幅（Layer4正規化に使用）
      double zone_band = zh - zl;
      if(zone_band <= 0.0) return az;

      //============================================================
      // LAYER1: HARD GATE
      // dist = (zl - price) / zl
      //   dist > 0  : price は zl より下方
      //   dist <= 0 : price は zl 以上（帯内または上方）
      // dist > 0.10 → AUTH_FAKE即返却（ATR取得より先に実行）
      //============================================================
      double dist = (zl - price) / zl;

      if(dist > 0.10)
        {
         az.verdict    = AUTH_FAKE;
         az.auth_score = 0.0;
         return az;
        }

      //============================================================
      // ATR取得（Layer3 pressure計算に使用）
      // HARD GATE通過後のみ実行（dist<=0.10の局面のみ）
      //============================================================
      double atr = 0.0;
      double atr_buf[];
      ArraySetAsSeries(atr_buf, true);
      if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buf) > 0)
         atr = atr_buf[0];
      if(atr <= 0.0) atr = r * 0.01;  // フォールバック（r×1%）

      //============================================================
      // LAYER2: ZONE STATE → zone_coherence
      // BREAKOUT : dist < -0.03  → 0.7
      // INSIDE   : dist <= 0.0  → 1.0
      // APPROACHING: dist <= 0.05 → 0.5
      // OUT      : else（dist 5〜10%）→ 0.0
      //============================================================
      double zone_coherence = 0.0;
      string state_str      = "OUT";

      if(dist < -0.03)
        { zone_coherence = 0.7; state_str = "BREAKOUT"; }
      else if(dist <= 0.0)
        { zone_coherence = 1.0; state_str = "INSIDE"; }
      else if(dist <= 0.05)
        { zone_coherence = 0.5; state_str = "APPROACHING"; }
      else
        { zone_coherence = 0.0; state_str = "OUT"; }

      //============================================================
      // LAYER3: PRESSURE
      // pressure       = |price - zl| / ATR
      // pressure_score = exp(-pressure)  ← 近いほど1.0に近づく
      //============================================================
      double pressure       = MathAbs(price - zl) / atr;
      double pressure_score = MathExp(-pressure);

      //============================================================
      // LAYER4: ZONE WICK SCORE
      // CalcZoneWick()で直近3本の最大拒絶ヒゲ長（価格単位）取得
      // 正規化: zone_band（帯幅）で除算
      // zone_wick_score = min(1.0, max_wick_len / zone_band)
      //============================================================
      double max_wick_len   = CalcZoneWick(zl, zh);
      double zone_wick_score= MathMin(1.0, max_wick_len / zone_band);

      //============================================================
      // LAYER5: CONTINUITY
      // CalcContinuityBars()で連続帯内本数を取得
      // continuity = min(1.0, continuity_bars / 5.0)
      // 5本連続INSIDEで上限1.0
      //============================================================
      int    continuity_bars = CalcContinuityBars(zl, zh);
      double continuity      = MathMin(1.0, (double)continuity_bars / 5.0);

      // bars_insideフィールドに連続帯内本数を格納（ダッシュボード用）
      az.bars_inside = continuity_bars;

      //============================================================
      // FINAL SCORE
      // 0.40 * zone_coherence
      // 0.25 * pressure_score
      // 0.20 * zone_wick_score
      // 0.15 * continuity
      //============================================================
      double final_score =
         0.40 * zone_coherence  +
         0.25 * pressure_score  +
         0.20 * zone_wick_score +
         0.15 * continuity;

      // auth_scoreフィールドに0〜100スケールで格納（互換維持）
      az.auth_score = MathMax(0.0, MathMin(100.0, final_score * 100.0));

      //============================================================
      // FINAL DECISION
      // > 0.65 → AUTH_REAL
      // > 0.35 → AUTH_PENDING
      // else   → AUTH_FAKE
      //============================================================
      if(final_score > 0.65)
         az.verdict = AUTH_REAL;
      else if(final_score > 0.35)
         az.verdict = AUTH_PENDING;
      else
         az.verdict = AUTH_FAKE;

      //============================================================
      // DEBUG LOG（ダッシュボード表示用: AUTH_SCORE DIST PRESSURE STATE）
      // ステートレス: 呼び出し元(OnCalculate)のnbフラグで制御
      // ここではPrint()のみ（static変数なし）
      //============================================================
      string verdict_str = (az.verdict==AUTH_REAL)   ? "AUTH_REAL"    :
                           (az.verdict==AUTH_PENDING) ? "AUTH_PENDING" : "AUTH_FAKE";
      string zone_type   = (price >= al+AUTH_TL*r)   ? "OUTER(3.77-4.236)"
                                                      : "INNER(2.33-2.618)";
      Print(
         "[AUTH_v32] ", _Symbol, " ", EnumToString(_Period),
         " | state=",   state_str,
         " | zone=",    zone_type,
         " | dist=",    DoubleToString(dist*100.0, 2), "%",
         " | press=",   DoubleToString(pressure, 3),
         " | pscore=",  DoubleToString(pressure_score, 3),
         " | wick=",    DoubleToString(max_wick_len, 2),
         " | wscore=",  DoubleToString(zone_wick_score, 3),
         " | cbars=",   continuity_bars,
         " | cont=",    DoubleToString(continuity, 3),
         " | zcoher=",  DoubleToString(zone_coherence, 2),
         " | fscore=",  DoubleToString(final_score, 4),
         " | score=",   DoubleToString(az.auth_score, 1),
         " | price=",   DoubleToString(price, 2),
         " | zl=",      DoubleToString(zl, 2),
         " | zh=",      DoubleToString(zh, 2),
         " | => ",      verdict_str
      );

      return az;
     }
  };

//+------------------------------------------------------------------+
//  CEnergy  — MAハンドルをInit/Deinitで管理
//+------------------------------------------------------------------+
class CEnergy
  {
private:
   int m_h1ema, m_ma200, m_ma50;

   double CalcRCI(int period,int shift)
     {
      double price[]; ArraySetAsSeries(price,true);
      if(CopyClose(_Symbol,PERIOD_CURRENT,shift,period,price)<period)
         return 0;
      double d=0;
      for(int i=0;i<period;i++)
        {
         int rt=i+1, rp=1;
         for(int j=0;j<period;j++)
            if(price[j]>price[i]) rp++;
         d+=MathPow((double)(rt-rp),2);
        }
      return(1.0-6.0*d/((double)period*((double)period*(double)period-1.0)))*100.0;
     }

   double DetectDivergence(string &label)
     {
      label="NONE";
      double rci_now =CalcRCI(9,0);
      double rci_prev=CalcRCI(9,5);
      double hi_now =iHigh(_Symbol,PERIOD_CURRENT,1);
      double hi_prev=iHigh(_Symbol,PERIOD_CURRENT,6);
      double lo_now =iLow (_Symbol,PERIOD_CURRENT,1);
      double lo_prev=iLow (_Symbol,PERIOD_CURRENT,6);
      double bias=0;
      if(hi_now>hi_prev&&rci_now<rci_prev){ label="BEAR DIV"; bias=-25; }
      else if(lo_now<lo_prev&&rci_now>rci_prev){ label="BULL DIV"; bias=+25; }
      return bias;
     }

public:
   bool Init()
     {
      m_h1ema=iMA(_Symbol,PERIOD_H1,     50, 0,MODE_EMA,PRICE_CLOSE);
      m_ma200=iMA(_Symbol,PERIOD_CURRENT,200,0,MODE_SMA,PRICE_CLOSE);
      m_ma50 =iMA(_Symbol,PERIOD_CURRENT, 50,0,MODE_EMA,PRICE_CLOSE);
      if(m_h1ema==INVALID_HANDLE||
         m_ma200==INVALID_HANDLE||
         m_ma50 ==INVALID_HANDLE) return false;
      return true;
     }

   EnergySnapshot Calc(CompressionState &cs,SweepState &ss,
                       TUTTO_PHASE phase,AuthZoneData &auth,
                       CMTFManager &mtf)
     {
      EnergySnapshot es;
      es.compression_pct=cs.score;
      es.phase=phase; es.prev_phase=g_last_phase;
      es.snapshot_time=TimeCurrent();
      es.liquidity_gravity_near=0;
      es.local_dir="DOWN"; es.macro_dir="DOWN";
      es.dir_warning="ALIGNED"; es.conflict_score=0;
      es.rel_compression=0; es.rel_structure=0;
      es.rel_sweep=0; es.rel_divergence=0;
      es.rel_volume=0; es.rel_mtf=0;
      es.divergence_label="NONE";
      es.release_dir=RELEASE_UNKNOWN;
      es.release_prob=0; es.release_quality=0;

      double price=iClose(_Symbol,PERIOD_CURRENT,0);
      if(price<=0) return es;

      double buf[]; ArraySetAsSeries(buf,true);
      double h1e_v=0,ma200_v=0,ma50_v=0;
      if(CopyBuffer(m_h1ema,0,0,1,buf)>0) h1e_v  =buf[0];
      if(CopyBuffer(m_ma200,0,0,1,buf)>0) ma200_v=buf[0];
      if(CopyBuffer(m_ma50, 0,0,1,buf)>0) ma50_v =buf[0];

      es.local_dir=(price>h1e_v&&h1e_v>0)?"UP":"DOWN";
      es.macro_dir=(mtf.IsH4Bull()&&mtf.IsD1Bull())?"UP":"DOWN";
      if(es.local_dir!=es.macro_dir)
        { es.conflict_score=75; es.dir_warning="CONFLICT"; }
      else
        { es.conflict_score=0;  es.dir_warning="ALIGNED"; }

      double bias=0;

      es.rel_compression=(cs.score>COMP_TRIG)?15.0:cs.score*0.15;

      double struct_score=0;
      if(ma200_v>0)
        { if(price>ma200_v) struct_score+=7; else struct_score-=7; }
      if(ma50_v>0)
        {
         if(price>ma50_v)  struct_score+=7; else struct_score-=7;
         if(ma50_v>ma200_v&&ma200_v>0) struct_score+=6;
         else if(ma200_v>0)            struct_score-=6;
        }
      es.rel_structure=MathAbs(struct_score);
      bias+=struct_score;

      double sweep_bias=0;
      if(ss.detected)
        {
         if(ss.direction==SWEEP_DOWN) sweep_bias=+20;
         if(ss.direction==SWEEP_UP)   sweep_bias=-20;
        }
      es.rel_sweep=MathAbs(sweep_bias);
      bias+=sweep_bias;

      double div_bias=DetectDivergence(es.divergence_label);
      es.rel_divergence=MathAbs(div_bias);
      bias+=div_bias;

      long vol[];
      if(CopyTickVolume(_Symbol,PERIOD_CURRENT,0,4,vol)>=4)
        {
         double va=0;
         for(int i=1;i<=3;i++) va+=(double)vol[i];
         va/=3;
         double vol_bias=0;
         if(va>0&&(double)vol[0]>va*1.3)
           {
            double c0=iClose(_Symbol,PERIOD_CURRENT,0);
            double o0=iOpen (_Symbol,PERIOD_CURRENT,0);
            if(c0>o0) vol_bias=+10; else vol_bias=-10;
           }
         es.rel_volume=MathAbs(vol_bias);
         bias+=vol_bias;
        }

      double mtf_bias=0;
      if(mtf.IsH4Bull()) mtf_bias+=5; else mtf_bias-=5;
      if(mtf.IsD1Bull()) mtf_bias+=5; else mtf_bias-=5;
      es.rel_mtf=MathAbs(mtf_bias);
      bias+=mtf_bias;

      if(bias>=15)       es.release_dir=RELEASE_UP;
      else if(bias<=-15) es.release_dir=RELEASE_DOWN;
      else               es.release_dir=RELEASE_UNKNOWN;

      double prob_raw=(MathAbs(bias)/80.0)*100.0;
      es.release_prob=MathMin(prob_raw,100.0);
      double rq=es.rel_compression+es.rel_sweep+
                es.rel_divergence+es.rel_volume+es.rel_mtf;
      es.release_quality=MathMin(rq,100.0);
      return es;
     }

   void Deinit()
     {
      if(m_h1ema!=INVALID_HANDLE) IndicatorRelease(m_h1ema);
      if(m_ma200!=INVALID_HANDLE) IndicatorRelease(m_ma200);
      if(m_ma50 !=INVALID_HANDLE) IndicatorRelease(m_ma50);
     }
  };

//+------------------------------------------------------------------+
//  CDash
//+------------------------------------------------------------------+
class CDash
  {
private:
   void L(string n,int x,int y,string t,color c,int fs=9)
     {
      string f=DASH_PFX+n;
      if(ObjectFind(0,f)<0) ObjectCreate(0,f,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,f,OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0,f,OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0,f,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetString (0,f,OBJPROP_TEXT,      t);
      ObjectSetInteger(0,f,OBJPROP_COLOR,     c);
      ObjectSetInteger(0,f,OBJPROP_FONTSIZE,  fs);
      ObjectSetString (0,f,OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0,f,OBJPROP_BACK,      false);
      ObjectSetInteger(0,f,OBJPROP_SELECTABLE,false);
     }
public:
   bool Init() { return true; }
   void Render(EnergySnapshot &es,CompressionState &cs,
               SweepState &ss,AuthZoneData &auth,
               SignalState &sig,bool nb)
     {
      int x=20,y=30,g=16;
      color pc=clrWhite;
      switch(es.phase)
        {
         case PHASE_EXHAUSTION:     pc=clrRed;    break;
         case PHASE_AUTHENTICATION: pc=clrYellow; break;
         case PHASE_DISTRIBUTION:   pc=clrOrange; break;
         case PHASE_RELEASE:        pc=clrLime;   break;
         case PHASE_EXPANSION:      pc=clrAqua;   break;
         case PHASE_COMPRESSION:    pc=clrGray;   break;
        }
      L("t", x,y,"== TUTTO MSE v3.0 ==",clrWhite,10); y+=g+4;
      L("pl",x,y,"PHASE:",clrSilver);
      L("pv",x+70,y,PhaseStr(es.phase),pc); y+=g;
      color cc=(cs.score>80)?clrRed:(cs.score>65)?clrYellow:clrGray;
      L("c",x,y,StringFormat("COMP: %3.0f%%",cs.score),cc); y+=g;
      string rd=""; color rc=clrGray;
      switch(es.release_dir)
        {
         case RELEASE_UP:      rd="REL:UP   "; rc=clrLime;   break;
         case RELEASE_DOWN:    rd="REL:DOWN "; rc=clrRed;    break;
         case RELEASE_UNKNOWN: rd="REL:?    "; rc=clrYellow; break;
        }
      L("r",x,y,rd+StringFormat("[%2.0f%%]",es.release_prob),rc); y+=g;
      color qc=(es.release_quality>=RQ_REAL)?clrLime:
               (es.release_quality>=RQ_FAKE)?clrYellow:clrRed;
      L("q",x,y,StringFormat("RQ:   %2.0f",es.release_quality),qc); y+=g;
      color dc=(es.conflict_score>50)?clrOrange:clrLime;
      L("d",x,y,"L:"+es.local_dir+" M:"+es.macro_dir,dc); y+=g;
      color divc=clrGray;
      if(es.divergence_label=="BEAR DIV")      divc=clrRed;
      else if(es.divergence_label=="BULL DIV") divc=clrLime;
      L("div",x,y,"DIV: "+es.divergence_label,divc); y+=g;
      string sw=ss.detected?
         StringFormat("SWEEP:%s[%.1f]",
            ss.direction==SWEEP_UP?"UP":"DN",ss.volume_spike)
         :"SWEEP:none";
      L("s",x,y,sw,ss.detected?clrYellow:clrGray); y+=g;
      string as2=""; color ac=clrGray;
      switch(auth.verdict)
        {
         case AUTH_REAL:    as2="AUTH:REAL";    ac=clrLime;   break;
         case AUTH_FAKE:    as2="AUTH:FAKE";    ac=clrRed;    break;
         case AUTH_PENDING: as2="AUTH:PENDING"; ac=clrYellow; break;
        }
      L("a",x,y,as2,ac); y+=g;
      if(sig.structure_broken)
         L("swrn",x,y,"!! STRUCTURE BROKEN !!",clrRed,10);
      else if(sig.structure_warning)
         L("swrn",x,y,StringFormat("! WARNING x%d",sig.warning_count),clrOrange,9);
      else
         L("swrn",x,y,"STRUCTURE: OK",clrLime,9);
      y+=g; y+=4;
      L("sep",x,y,"--- REL SCORE ---",clrDimGray,8); y+=14;
      L("rs1",x,y,StringFormat("COMP:%.0f STR:%.0f",
         es.rel_compression,es.rel_structure),clrDimGray,8); y+=13;
      L("rs2",x,y,StringFormat("SWP:%.0f  DIV:%.0f",
         es.rel_sweep,es.rel_divergence),clrDimGray,8); y+=13;
      L("rs3",x,y,StringFormat("VOL:%.0f  MTF:%.0f",
         es.rel_volume,es.rel_mtf),clrDimGray,8); y+=14;
      L("ph_sep",x,y,"--- PHASE LOG ---",clrDimGray,8); y+=14;
      int st=MathMax(0,g_phase_hist_count-4);
      for(int i=st;i<g_phase_hist_count;i++)
        {
         string ts=TimeToString(g_phase_times[i],TIME_MINUTES);
         L("ph"+IntegerToString(i),x,y,
           ts+" "+PhaseStr(g_phase_history[i]),clrDimGray,8);
         y+=13;
        }
      // --- デバッグカウンター表示 ---
      y+=4;
      L("dbg_sep",x,y,"--- DEBUG ---",clrDimGray,8); y+=14;
      L("dbg_buy", x,y,StringFormat("BUY  DETECT:%d",g_detect_count_buy), clrAqua,9);  y+=13;
      L("dbg_sell",x,y,StringFormat("SELL DETECT:%d",g_detect_count_sell),clrRed, 9);  y+=13;
      // SETUP表示 (SWEEP不要・AUTH+RELのみ)
      color sc_buy  = sig.buy_setup  ? clrAqua   : clrDimGray;
      color sc_sell = sig.sell_setup ? clrRed     : clrDimGray;
      L("dbg_bsetup",x,y,StringFormat("BUY  SETUP :%d",sig.setup_count_buy), sc_buy, 9);  y+=13;
      L("dbg_ssetup",x,y,StringFormat("SELL SETUP :%d",sig.setup_count_sell),sc_sell,9);  y+=13;
      if(nb) ChartRedraw(0);
     }
   void Deinit() { ObjectsDeleteAll(0,DASH_PFX); }
  };

//+------------------------------------------------------------------+
//  グローバルインスタンス
//+------------------------------------------------------------------+
CMTFManager  g_mtf;
CCompression g_comp;
CSweep       g_sweep;
CPhase       g_phase;
CAuth        g_auth;
CEnergy      g_energy;
CDash        g_dash;

//+------------------------------------------------------------------+
//  InitSignalState
//+------------------------------------------------------------------+
void InitSignalState(SignalState &s)
  {
   s.active=false; s.pending=false; s.pending_direction=0;
   s.signal_bar_time=0; s.direction=0; s.entry_price=0;
   s.tp1=0; s.tp2=0; s.tp3=0; s.sl=0;
   s.structure_break_level=0; s.entry_time=0;
   s.tp1_hit=false; s.tp2_hit=false;
   s.tp3_hit=false; s.sl_hit=false; s.trade_finished=false;
   s.rr1=0; s.rr2=0; s.rr3=0;
   s.swing_high_used=0; s.swing_low_used=0;
   s.structure_warning=false; s.structure_broken=false;
   s.warning_count=0;
   s.auth_alerted=false; s.rel_alerted=false;
   s.rq_alerted=false; s.warn_broken_alerted=false;
   s.buy_setup=false; s.sell_setup=false;
   s.setup_count_buy=0; s.setup_count_sell=0;
  }

//+------------------------------------------------------------------+
//  InitSwingPoints
//+------------------------------------------------------------------+
void InitSwingPoints(SwingPoints &sp)
  {
   sp.swing_high=0; sp.swing_low=0;
   sp.sh_bar_index=0; sp.sl_bar_index=0;
   sp.sh_time=0; sp.sl_time=0;
   sp.range=0; sp.is_valid=false; sp.pattern=PATTERN_NONE;
  }

//+------------------------------------------------------------------+
//  PhaseStr
//+------------------------------------------------------------------+
string PhaseStr(TUTTO_PHASE p)
  {
   switch(p)
     {
      case PHASE_EXHAUSTION:     return "EXHAUSTION";
      case PHASE_AUTHENTICATION: return "AUTHENTICATION";
      case PHASE_DISTRIBUTION:   return "DISTRIBUTION";
      case PHASE_RELEASE:        return "RELEASE";
      case PHASE_EXPANSION:      return "EXPANSION";
      case PHASE_COMPRESSION:    return "COMPRESSION";
     }
   return "UNKNOWN";
  }

//+------------------------------------------------------------------+
//  CheckPhaseTransition
//+------------------------------------------------------------------+
void CheckPhaseTransition(TUTTO_PHASE new_phase,EnergySnapshot &es)
  {
   if(new_phase==g_last_phase) return;
   if(g_phase_hist_count<PHASE_HIST_MAX)
     {
      g_phase_history[g_phase_hist_count]=new_phase;
      g_phase_times  [g_phase_hist_count]=TimeCurrent();
      g_phase_hist_count++;
     }
   else
     {
      for(int i=0;i<PHASE_HIST_MAX-1;i++)
        {
         g_phase_history[i]=g_phase_history[i+1];
         g_phase_times  [i]=g_phase_times  [i+1];
        }
      g_phase_history[PHASE_HIST_MAX-1]=new_phase;
      g_phase_times  [PHASE_HIST_MAX-1]=TimeCurrent();
     }
   string phases[6]={"EXHAUSTION","AUTHENTICATION","DISTRIBUTION",
                      "RELEASE","EXPANSION","COMPRESSION"};
   string dir_str=(es.release_dir==RELEASE_UP)?"UP":
                  (es.release_dir==RELEASE_DOWN)?"DOWN":"?";
   string msg=StringFormat(
      "TUTTO PHASE SHIFT\n%s -> %s\nREL:%s [%.0f%%]\nRQ:%.0f\nDIV:%s",
      phases[(int)g_last_phase],phases[(int)new_phase],
      dir_str,es.release_prob,es.release_quality,
      es.divergence_label);
   Alert(msg);
   g_last_phase=new_phase;
  }

//+------------------------------------------------------------------+
//  CalcSwingPoints
//+------------------------------------------------------------------+
bool CalcSwingPoints(SwingPoints &sp,int direction,
                     int rates_total,double atr14_val)
  {
   InitSwingPoints(sp);
   if(rates_total<5) return false;
   double hi[],lo[]; datetime t[];
   ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
   ArraySetAsSeries(t, true);
   int copy_len=MathMin(SWING_SEARCH+5,rates_total);
   if(CopyHigh(_Symbol,PERIOD_CURRENT,0,copy_len,hi)<copy_len) return false;
   if(CopyLow (_Symbol,PERIOD_CURRENT,0,copy_len,lo)<copy_len) return false;
   if(CopyTime(_Symbol,PERIOD_CURRENT,0,copy_len,t) <copy_len) return false;
   int max_i=copy_len-3;
   if(direction==1)
     {
      int sh_idx=-1;
      for(int i=2;i<=max_i;i++)
         if(hi[i]>hi[i-1]&&hi[i]>hi[i-2]&&hi[i]>hi[i+1]&&hi[i]>hi[i+2])
           { sh_idx=i; break; }
      if(sh_idx<0)
        { Print("[DBG][SWING] BUY FAIL: FractalSH未検出 rates=",rates_total); return false; }
      int sl_idx=-1;
      int sl_end=MathMin(SWING_SEARCH,max_i);
      for(int i=sh_idx+1;i<=sl_end;i++)
        {
         if(i<2||i+2>=copy_len) continue;
         if(lo[i]<lo[i-1]&&lo[i]<lo[i-2]&&lo[i]<lo[i+1]&&lo[i]<lo[i+2])
           { sl_idx=i; break; }
        }
      if(sl_idx<0)
        { Print("[DBG][SWING] BUY FAIL: FractalSL未検出 SH_idx=",sh_idx); return false; }
      if(hi[sh_idx]<=lo[sl_idx])
        { Print("[DBG][SWING] BUY FAIL: 価格逆転 SH=",hi[sh_idx]," SL=",lo[sl_idx]); return false; }
      double rng=hi[sh_idx]-lo[sl_idx];
      if(atr14_val>0&&rng<atr14_val*ATR_SWING_MULT)
        { Print("[DBG][SWING] BUY FAIL: ATRフィルタ range=",DoubleToString(rng,5)," ATR*1.5=",DoubleToString(atr14_val*ATR_SWING_MULT,5)); return false; }
      sp.swing_high=hi[sh_idx]; sp.swing_low=lo[sl_idx];
      sp.sh_bar_index=sh_idx;   sp.sl_bar_index=sl_idx;
      sp.sh_time=t[sh_idx];     sp.sl_time=t[sl_idx];
      sp.range=rng; sp.is_valid=true;
      sp.pattern=PATTERN_LOW_TO_HIGH;
      Print("[DBG][SWING] BUY OK SH=",DoubleToString(sp.swing_high,5),
            " SL=",DoubleToString(sp.swing_low,5),
            " range=",DoubleToString(sp.range,5),
            " SH_bar=",sh_idx," SL_bar=",sl_idx);
      return true;
     }
   else
     {
      int sl_idx=-1;
      for(int i=2;i<=max_i;i++)
         if(lo[i]<lo[i-1]&&lo[i]<lo[i-2]&&lo[i]<lo[i+1]&&lo[i]<lo[i+2])
           { sl_idx=i; break; }
      if(sl_idx<0)
        { Print("[DBG][SWING] SELL FAIL: FractalSL未検出 rates=",rates_total); return false; }
      int sh_idx=-1;
      int sh_end=MathMin(SWING_SEARCH,max_i);
      for(int i=sl_idx+1;i<=sh_end;i++)
        {
         if(i<2||i+2>=copy_len) continue;
         if(hi[i]>hi[i-1]&&hi[i]>hi[i-2]&&hi[i]>hi[i+1]&&hi[i]>hi[i+2])
           { sh_idx=i; break; }
        }
      if(sh_idx<0)
        { Print("[DBG][SWING] SELL FAIL: FractalSH未検出 SL_idx=",sl_idx); return false; }
      if(hi[sh_idx]<=lo[sl_idx])
        { Print("[DBG][SWING] SELL FAIL: 価格逆転 SH=",hi[sh_idx]," SL=",lo[sl_idx]); return false; }
      double rng=hi[sh_idx]-lo[sl_idx];
      if(atr14_val>0&&rng<atr14_val*ATR_SWING_MULT)
        { Print("[DBG][SWING] SELL FAIL: ATRフィルタ range=",DoubleToString(rng,5)," ATR*1.5=",DoubleToString(atr14_val*ATR_SWING_MULT,5)); return false; }
      sp.swing_high=hi[sh_idx]; sp.swing_low=lo[sl_idx];
      sp.sh_bar_index=sh_idx;   sp.sl_bar_index=sl_idx;
      sp.sh_time=t[sh_idx];     sp.sl_time=t[sl_idx];
      sp.range=rng; sp.is_valid=true;
      sp.pattern=PATTERN_HIGH_TO_LOW;
      Print("[DBG][SWING] SELL OK SH=",DoubleToString(sp.swing_high,5),
            " SL=",DoubleToString(sp.swing_low,5),
            " range=",DoubleToString(sp.range,5),
            " SH_bar=",sh_idx," SL_bar=",sl_idx);
      return true;
     }
  }

//+------------------------------------------------------------------+
//  CalcTPSL
//+------------------------------------------------------------------+
void CalcTPSL(SwingPoints &sp,SignalState &sig)
  {
   if(!sp.is_valid||sp.range<=0) return;
   if(sig.direction==1)
     {
      double base=sp.swing_low;
      sig.tp1=base+(3.236*sp.range);
      sig.tp2=base+(4.236*sp.range);
      sig.tp3=base+(6.854*sp.range);
      sig.sl=sp.swing_low;
      sig.structure_break_level=base+(2.618*sp.range);
     }
   else
     {
      double base=sp.swing_high;
      sig.tp1=base-(3.236*sp.range);
      sig.tp2=base-(4.236*sp.range);
      sig.tp3=base-(6.854*sp.range);
      sig.sl=sp.swing_high;
      sig.structure_break_level=base-(2.618*sp.range);
     }
   sig.swing_high_used=sp.swing_high;
   sig.swing_low_used =sp.swing_low;
   double risk=MathAbs(sig.entry_price-sig.sl);
   if(risk>_Point)
     {
      sig.rr1=MathAbs(sig.tp1-sig.entry_price)/risk;
      sig.rr2=MathAbs(sig.tp2-sig.entry_price)/risk;
      sig.rr3=MathAbs(sig.tp3-sig.entry_price)/risk;
     }
  }

//+------------------------------------------------------------------+
//  DeleteSignalObjects
//+------------------------------------------------------------------+
void DeleteSignalObjects()
  {
   string names[]=
     {
      SIG_PFX+"ARROW",  SIG_PFX+"ENTRY_LBL",
      SIG_PFX+"TP1",    SIG_PFX+"TP1_LBL",
      SIG_PFX+"TP2",    SIG_PFX+"TP2_LBL",
      SIG_PFX+"TP3",    SIG_PFX+"TP3_LBL",
      SIG_PFX+"SL",     SIG_PFX+"SL_LBL",
      SIG_PFX+"SBL",    SIG_PFX+"SBL_LBL",
      SIG_PFX+"RR"
     };
   int total=ArraySize(names);
   for(int i=0;i<total;i++)
      if(ObjectFind(0,names[i])>=0) ObjectDelete(0,names[i]);
  }

//+------------------------------------------------------------------+
//  DrawHLineSig
//+------------------------------------------------------------------+
void DrawHLineSig(string name,double price,color clr,
                  int style,string tooltip)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_HLINE,0,0,price)) return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,     style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,     1);
   ObjectSetString (0,name,OBJPROP_TOOLTIP,   tooltip);
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
//  DrawTextSig
//+------------------------------------------------------------------+
void DrawTextSig(string name,double price,string txt,color clr)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   datetime lbl=(datetime)(TimeCurrent()+
                 (long)PeriodSeconds(PERIOD_CURRENT)*3);
   if(!ObjectCreate(0,name,OBJ_TEXT,0,lbl,price)) return;
   ObjectSetString (0,name,OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  9);
   ObjectSetString (0,name,OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,    ANCHOR_LEFT);
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
//  DrawRR
//+------------------------------------------------------------------+
void DrawRR(SignalState &sig)
  {
   double risk=MathAbs(sig.entry_price-sig.sl);
   if(risk<=_Point) return;
   string name=SIG_PFX+"RR";
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0)) return;
   string txt=StringFormat("RR  TP1 1:%.1f   TP2 1:%.1f   TP3 1:%.1f",
                            sig.rr1,sig.rr2,sig.rr3);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
   ObjectSetString (0,name,OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  10);
   ObjectSetString (0,name,OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
//  DrawEntryObjects
//+------------------------------------------------------------------+
void DrawEntryObjects(SignalState &sig)
  {
   Print("[DBG][DRAW] DrawEntryObjects fired dir=",sig.direction,
         " entry=",DoubleToString(sig.entry_price,5),
         " TP1=",DoubleToString(sig.tp1,5),
         " TP2=",DoubleToString(sig.tp2,5),
         " TP3=",DoubleToString(sig.tp3,5),
         " SL=", DoubleToString(sig.sl,5));
   DeleteSignalObjects();
   datetime bt=sig.entry_time;
   if(sig.direction==1)
     {
      string arr=SIG_PFX+"ARROW";
      bool ok=ObjectCreate(0,arr,OBJ_ARROW_BUY,0,bt,sig.entry_price);
      Print("[DBG][DRAW] ARROW_BUY Create=",ok," err=",GetLastError());
      if(!ok) return;
      ObjectSetInteger(0,arr,OBJPROP_COLOR,     clrAqua);
      ObjectSetInteger(0,arr,OBJPROP_WIDTH,     2);
      ObjectSetInteger(0,arr,OBJPROP_ANCHOR,    ANCHOR_TOP);
      ObjectSetInteger(0,arr,OBJPROP_BACK,      false);
      ObjectSetInteger(0,arr,OBJPROP_SELECTABLE,false);
      DrawTextSig(SIG_PFX+"ENTRY_LBL",sig.entry_price,"▲ BUY ENTRY",clrAqua);
     }
   else
     {
      string arr=SIG_PFX+"ARROW";
      bool ok=ObjectCreate(0,arr,OBJ_ARROW_SELL,0,bt,sig.entry_price);
      Print("[DBG][DRAW] ARROW_SELL Create=",ok," err=",GetLastError());
      if(!ok) return;
      ObjectSetInteger(0,arr,OBJPROP_COLOR,     clrRed);
      ObjectSetInteger(0,arr,OBJPROP_WIDTH,     2);
      ObjectSetInteger(0,arr,OBJPROP_ANCHOR,    ANCHOR_BOTTOM);
      ObjectSetInteger(0,arr,OBJPROP_BACK,      false);
      ObjectSetInteger(0,arr,OBJPROP_SELECTABLE,false);
      DrawTextSig(SIG_PFX+"ENTRY_LBL",sig.entry_price,"▼ SELL ENTRY",clrRed);
     }
   DrawHLineSig(SIG_PFX+"TP1",sig.tp1,clrLime,   STYLE_DASH, "TP1 Fib3.236");
   DrawTextSig (SIG_PFX+"TP1_LBL",sig.tp1,"TP1",clrLime);
   DrawHLineSig(SIG_PFX+"TP2",sig.tp2,clrGreen,  STYLE_DASH, "TP2 Fib4.236");
   DrawTextSig (SIG_PFX+"TP2_LBL",sig.tp2,"TP2",clrGreen);
   DrawHLineSig(SIG_PFX+"TP3",sig.tp3,clrGold,   STYLE_DASH, "TP3 Fib6.854");
   DrawTextSig (SIG_PFX+"TP3_LBL",sig.tp3,"TP3",clrGold);
   DrawHLineSig(SIG_PFX+"SL", sig.sl, clrCrimson,STYLE_SOLID,"SL (TradeStop)");
   DrawTextSig (SIG_PFX+"SL_LBL", sig.sl, "SL", clrCrimson);
   Print("[DBG][DRAW] HLines drawn TP1=",DoubleToString(sig.tp1,5),
         " TP2=",DoubleToString(sig.tp2,5),
         " TP3=",DoubleToString(sig.tp3,5),
         " SL=", DoubleToString(sig.sl,5));
   if(sig.structure_break_level>0)
     {
      DrawHLineSig(SIG_PFX+"SBL",sig.structure_break_level,
                   clrOrange,STYLE_DOT,"StructureBreak Fib2.618");
      DrawTextSig(SIG_PFX+"SBL_LBL",sig.structure_break_level,
                  "STRUCTURE BREAK",clrOrange);
     }
   DrawRR(sig);
   ChartRedraw(0);
   Print("[DBG][DRAW] DrawEntryObjects complete");
  }

//+------------------------------------------------------------------+
//  FireSignalAlert — 価格系専用  ※(void)キャスト不使用
//+------------------------------------------------------------------+
void FireSignalAlert(string event_type,SignalState &sig)
  {
   string dir=(sig.direction==1)?"BUY":"SELL";
   string msg="";
   if(event_type=="BUY_ENTRY")
      msg=StringFormat("[TUTTO] %s BUY ENTRY @ %.5f",_Symbol,sig.entry_price);
   else if(event_type=="SELL_ENTRY")
      msg=StringFormat("[TUTTO] %s SELL ENTRY @ %.5f",_Symbol,sig.entry_price);
   else if(event_type=="TP1")
      msg=StringFormat("[TUTTO] %s TP1 @ %.5f RR1:%.1f",_Symbol,sig.tp1,sig.rr1);
   else if(event_type=="TP2")
      msg=StringFormat("[TUTTO] %s TP2 @ %.5f RR1:%.1f",_Symbol,sig.tp2,sig.rr2);
   else if(event_type=="TP3")
      msg=StringFormat("[TUTTO] %s TP3 @ %.5f RR1:%.1f",_Symbol,sig.tp3,sig.rr3);
   else if(event_type=="SL")
      msg=StringFormat("[TUTTO] %s SL @ %.5f DIR:%s",_Symbol,sig.sl,dir);
   if(msg=="") return;
   Alert(msg);
   SendNotification(msg);
   Print(msg);
  }

//+------------------------------------------------------------------+
//  FireStructureAlert — 構造系専用  ※(void)キャスト不使用
//+------------------------------------------------------------------+
void FireStructureAlert(string alert_type,string level,
                        SignalState &sig)
  {
   string dir=(sig.direction==1)?"BUY":"SELL";
   string msg="";
   if(alert_type=="AUTH_LOST")
     {
      if(level=="WARNING")
         msg=StringFormat("[TUTTO] AUTH WARNING %s %s PENDING @ %.5f",
                          _Symbol,dir,sig.entry_price);
      else
         msg=StringFormat("[TUTTO] AUTH LOST %s %s FAKE @ %.5f",
                          _Symbol,dir,sig.entry_price);
     }
   else if(alert_type=="REL_REVERSED")
     {
      if(level=="WARNING")
         msg=StringFormat("[TUTTO] REL WARNING %s %s UNKNOWN @ %.5f",
                          _Symbol,dir,sig.entry_price);
      else
         msg=StringFormat("[TUTTO] REL REVERSED %s %s @ %.5f",
                          _Symbol,dir,sig.entry_price);
     }
   else if(alert_type=="STRUCTURE_BREAK")
     {
      if(level=="WARNING")
         msg=StringFormat("[TUTTO] RQ WARNING %s RQ 50-70",_Symbol);
      else if(level=="BROKEN")
         msg=StringFormat("[TUTTO] STRUCTURE BREAK %s RQ<50",_Symbol);
      else
         msg=StringFormat("[TUTTO] STRUCTURE BREAK %s WARN x%d",
                          _Symbol,sig.warning_count);
     }
   if(msg=="") return;
   Alert(msg);
   SendNotification(msg);
   Print(msg);
  }

//+------------------------------------------------------------------+
//  DetectSetup — SWEEP不要・AUTH_REAL + REL方向のみで成立
//  SETUPはシグナル(DETECT)の前段階通知
//+------------------------------------------------------------------+
void DetectSetup(EnergySnapshot &es, AuthZoneData &auth,
                 SignalState &sig)
  {
   // アクティブ中・ペンディング中はスキップ
   if(sig.active || sig.pending) return;

   bool buy_setup  = (auth.verdict  == AUTH_REAL) &&
                     (es.release_dir == RELEASE_UP);
   bool sell_setup = (auth.verdict  == AUTH_REAL) &&
                     (es.release_dir == RELEASE_DOWN);

   // BUY SETUP
   if(buy_setup && !sig.buy_setup)
     {
      sig.buy_setup  = true;
      sig.sell_setup = false;
      sig.setup_count_buy++;
      Print("[DBG][SETUP] *** BUY SETUP *** #",sig.setup_count_buy,
            " AUTH=REAL REL=UP RQ=",DoubleToString(es.release_quality,1));
     }
   // SELL SETUP
   else if(sell_setup && !sig.sell_setup)
     {
      sig.sell_setup = true;
      sig.buy_setup  = false;
      sig.setup_count_sell++;
      Print("[DBG][SETUP] *** SELL SETUP *** #",sig.setup_count_sell,
            " AUTH=REAL REL=DOWN RQ=",DoubleToString(es.release_quality,1));
     }
   // 条件不成立でリセット
   else if(!buy_setup && !sell_setup)
     {
      sig.buy_setup  = false;
      sig.sell_setup = false;
     }
  }

//+------------------------------------------------------------------+
//  DetectBuySell
//+------------------------------------------------------------------+
void DetectBuySell(EnergySnapshot &es,SweepState &ss,
                   AuthZoneData &auth,SignalState &sig,
                   int rates_total)
  {
   if(sig.active||sig.pending) return;
   if(rates_total<5) return;
   datetime cur_bar=iTime(_Symbol,PERIOD_CURRENT,0);
   if(cur_bar==0) return;
   if(sig.signal_bar_time==cur_bar) return;
   bool buy_cond =(auth.verdict==AUTH_REAL&&
                   es.release_dir==RELEASE_UP&&
                   ss.direction==SWEEP_DOWN&&
                   es.release_quality>=RQ_REAL);
   bool sell_cond=(auth.verdict==AUTH_REAL&&
                   es.release_dir==RELEASE_DOWN&&
                   ss.direction==SWEEP_UP&&
                   es.release_quality>=RQ_REAL);
   if(!buy_cond&&!sell_cond)
     {
      // 条件不成立の詳細ログ (nbのみ出力して毎Tick汚染を防ぐ)
      Print("[DBG][DETECT] MISS auth=",auth.verdict,
            " rel=",es.release_dir,
            " sweep=",ss.direction,
            " rq=",DoubleToString(es.release_quality,1));
      return;
     }
   sig.pending_direction  =buy_cond?1:-1;
   sig.pending            =true;
   sig.signal_bar_time    =cur_bar;
   sig.structure_warning  =false;
   sig.structure_broken   =false;
   sig.warning_count      =0;
   sig.auth_alerted       =false;
   sig.rel_alerted        =false;
   sig.rq_alerted         =false;
   sig.warn_broken_alerted=false;
   sig.trade_finished     =false;
   if(buy_cond)
     {
      g_detect_count_buy++;
      Print("[DBG][DETECT] *** BUY PENDING *** #",g_detect_count_buy,
            " bar=",TimeToString(cur_bar,TIME_DATE|TIME_MINUTES));
     }
   else
     {
      g_detect_count_sell++;
      Print("[DBG][DETECT] *** SELL PENDING *** #",g_detect_count_sell,
            " bar=",TimeToString(cur_bar,TIME_DATE|TIME_MINUTES));
     }
  }

//+------------------------------------------------------------------+
//  MonitorTPSL — 価格管理専用 / SymbolInfoDouble(BID)使用
//+------------------------------------------------------------------+
void MonitorTPSL(SignalState &sig)
  {
   if(!sig.active) return;
   double cur=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(cur<=0) return;
   if(sig.direction==1)
     {
      if(!sig.tp1_hit&&cur>=sig.tp1)
        { sig.tp1_hit=true;
          Print("[DBG][TPSL] BUY TP1 HIT cur=",DoubleToString(cur,5)," tp1=",DoubleToString(sig.tp1,5));
          FireSignalAlert("TP1",sig); }
      if(!sig.tp2_hit&&cur>=sig.tp2)
        { sig.tp2_hit=true;
          Print("[DBG][TPSL] BUY TP2 HIT cur=",DoubleToString(cur,5)," tp2=",DoubleToString(sig.tp2,5));
          FireSignalAlert("TP2",sig); }
      if(!sig.tp3_hit&&cur>=sig.tp3)
        { sig.tp3_hit=true; sig.trade_finished=true; sig.active=false;
          Print("[DBG][TPSL] BUY TP3 HIT cur=",DoubleToString(cur,5)," tp3=",DoubleToString(sig.tp3,5));
          FireSignalAlert("TP3",sig); DeleteSignalObjects(); return; }
      if(!sig.sl_hit&&cur<=sig.sl)
        { sig.sl_hit=true; sig.trade_finished=true; sig.active=false;
          Print("[DBG][TPSL] BUY SL HIT cur=",DoubleToString(cur,5)," sl=",DoubleToString(sig.sl,5));
          FireSignalAlert("SL",sig); DeleteSignalObjects(); return; }
     }
   else
     {
      if(!sig.tp1_hit&&cur<=sig.tp1)
        { sig.tp1_hit=true;
          Print("[DBG][TPSL] SELL TP1 HIT cur=",DoubleToString(cur,5)," tp1=",DoubleToString(sig.tp1,5));
          FireSignalAlert("TP1",sig); }
      if(!sig.tp2_hit&&cur<=sig.tp2)
        { sig.tp2_hit=true;
          Print("[DBG][TPSL] SELL TP2 HIT cur=",DoubleToString(cur,5)," tp2=",DoubleToString(sig.tp2,5));
          FireSignalAlert("TP2",sig); }
      if(!sig.tp3_hit&&cur<=sig.tp3)
        { sig.tp3_hit=true; sig.trade_finished=true; sig.active=false;
          Print("[DBG][TPSL] SELL TP3 HIT cur=",DoubleToString(cur,5)," tp3=",DoubleToString(sig.tp3,5));
          FireSignalAlert("TP3",sig); DeleteSignalObjects(); return; }
      if(!sig.sl_hit&&cur>=sig.sl)
        { sig.sl_hit=true; sig.trade_finished=true; sig.active=false;
          Print("[DBG][TPSL] SELL SL HIT cur=",DoubleToString(cur,5)," sl=",DoubleToString(sig.sl,5));
          FireSignalAlert("SL",sig); DeleteSignalObjects(); return; }
     }
  }

//+------------------------------------------------------------------+
//  MonitorAuth
//+------------------------------------------------------------------+
void MonitorAuth(SignalState &sig,AuthZoneData &auth,
                 AUTH_VERDICT prev_a)
  {
   if(prev_a!=AUTH_REAL) return;
   if(auth.verdict==AUTH_FAKE&&!sig.auth_alerted)
     { sig.structure_broken=true; sig.auth_alerted=true;
       FireStructureAlert("AUTH_LOST","BROKEN",sig); }
   else if(auth.verdict==AUTH_PENDING&&!sig.auth_alerted)
     { sig.structure_warning=true; sig.auth_alerted=true;
       FireStructureAlert("AUTH_LOST","WARNING",sig); }
  }

//+------------------------------------------------------------------+
//  MonitorREL
//+------------------------------------------------------------------+
void MonitorREL(SignalState &sig,EnergySnapshot &es,
                RELEASE_DIR prev_r)
  {
   if(sig.direction==1)
     {
      if(prev_r==RELEASE_UP)
        {
         if(es.release_dir==RELEASE_DOWN&&!sig.rel_alerted)
           { sig.structure_broken=true; sig.rel_alerted=true;
             FireStructureAlert("REL_REVERSED","BROKEN",sig); }
         else if(es.release_dir==RELEASE_UNKNOWN&&!sig.rel_alerted)
           { sig.structure_warning=true; sig.rel_alerted=true;
             FireStructureAlert("REL_REVERSED","WARNING",sig); }
        }
     }
   else
     {
      if(prev_r==RELEASE_DOWN)
        {
         if(es.release_dir==RELEASE_UP&&!sig.rel_alerted)
           { sig.structure_broken=true; sig.rel_alerted=true;
             FireStructureAlert("REL_REVERSED","BROKEN",sig); }
         else if(es.release_dir==RELEASE_UNKNOWN&&!sig.rel_alerted)
           { sig.structure_warning=true; sig.rel_alerted=true;
             FireStructureAlert("REL_REVERSED","WARNING",sig); }
        }
     }
  }

//+------------------------------------------------------------------+
//  MonitorRQ
//+------------------------------------------------------------------+
void MonitorRQ(SignalState &sig,EnergySnapshot &es,double prev_q)
  {
   if(prev_q<RQ_REAL) return;
   if(es.release_quality<RQ_WARN_LOW&&!sig.rq_alerted)
     { sig.structure_broken=true; sig.rq_alerted=true;
       FireStructureAlert("STRUCTURE_BREAK","BROKEN",sig); }
   else if(es.release_quality<RQ_REAL&&
           es.release_quality>=RQ_WARN_LOW&&!sig.rq_alerted)
     { sig.structure_warning=true; sig.rq_alerted=true;
       FireStructureAlert("STRUCTURE_BREAK","WARNING",sig); }
  }

//+------------------------------------------------------------------+
//  MonitorStructure
//+------------------------------------------------------------------+
void MonitorStructure(SignalState &sig,AuthZoneData &auth,
                      EnergySnapshot &es)
  {
   if(!sig.active) return;
   AUTH_VERDICT prev_a=g_prev_auth;
   RELEASE_DIR  prev_r=g_prev_rel;
   double       prev_q=g_prev_rq;
   MonitorAuth(sig,auth,prev_a);
   MonitorREL (sig,es,  prev_r);
   MonitorRQ  (sig,es,  prev_q);
   int wc=0;
   if(!sig.structure_broken)
     {
      if(sig.auth_alerted&&auth.verdict==AUTH_PENDING) wc++;
      if(sig.rel_alerted&&es.release_dir==RELEASE_UNKNOWN) wc++;
      if(sig.rq_alerted&&
         es.release_quality>=RQ_WARN_LOW&&
         es.release_quality< RQ_REAL) wc++;
     }
   sig.warning_count=wc;
   if(!sig.structure_broken&&sig.warning_count>=2&&
      !sig.warn_broken_alerted)
     {
      sig.structure_broken    =true;
      sig.warn_broken_alerted =true;
      FireStructureAlert("STRUCTURE_BREAK","BROKEN_BY_WARNING",sig);
     }
   g_prev_auth=auth.verdict;
   g_prev_rel =es.release_dir;
   g_prev_rq  =es.release_quality;
  }

//+------------------------------------------------------------------+
//  OnInit
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_mtf.Init())    return INIT_FAILED;
   if(!g_comp.Init())   return INIT_FAILED;
   if(!g_sweep.Init())  return INIT_FAILED;
   if(!g_phase.Init())  return INIT_FAILED;
   if(!g_energy.Init()) return INIT_FAILED;
   if(!g_dash.Init())   return INIT_FAILED;
   g_phase_hist_count=0;
   g_last_phase=PHASE_COMPRESSION;
   for(int i=0;i<PHASE_HIST_MAX;i++)
     { g_phase_history[i]=PHASE_COMPRESSION; g_phase_times[i]=0; }
   g_prev_auth=AUTH_PENDING;
   g_prev_rel =RELEASE_UNKNOWN;
   g_prev_rq  =0.0;
   g_detect_count_buy  =0;
   g_detect_count_sell =0;
   InitSignalState(g_signal);
   InitSwingPoints(g_swing);
   EventSetTimer(MTF_SEC);
   g_mtf.Update();
   IndicatorSetString(INDICATOR_SHORTNAME,"TUTTO MASTER OS v3.1-debug");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//  OnTimer
//+------------------------------------------------------------------+
void OnTimer() { g_mtf.Update(); }

//+------------------------------------------------------------------+
//  OnCalculate
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
   if(rates_total<200) return 0;

   // NewBar判定 — iTime()ベース (配列方向依存なし)
   static datetime s_last_bar=0;
   datetime cur_bar=iTime(_Symbol,_Period,0);
   if(cur_bar==0) return prev_calculated;
   bool nb=(cur_bar!=s_last_bar);
   if(nb) s_last_bar=cur_bar;

   // BLOCK-A: Pending執行 (nbのみ)
   if(nb&&g_signal.pending)
     {
      g_signal.direction  =g_signal.pending_direction;
      g_signal.entry_price=iOpen(_Symbol,_Period,0); // 次バーOpen
      g_signal.entry_time =cur_bar;
      double atr_val=0;
      double atr_buf[]; ArraySetAsSeries(atr_buf,true);
      if(CopyBuffer(g_comp.GetATRHandle(),0,0,1,atr_buf)>0)
         atr_val=atr_buf[0];
      if(CalcSwingPoints(g_swing,g_signal.direction,rates_total,atr_val))
        {
         CalcTPSL(g_swing,g_signal);
         DrawEntryObjects(g_signal);
         DrawRR(g_signal);
         string et=(g_signal.direction==1)?"BUY_ENTRY":"SELL_ENTRY";
         FireSignalAlert(et,g_signal);
         g_signal.active=true;
        }
      g_signal.pending=false;
     }

   // 既存処理
   CompressionState cs=g_comp.Calc(nb);
   SweepState       ss=g_sweep.Detect(nb);
   double price=iClose(_Symbol,PERIOD_CURRENT,0);
   double h20=0,l20=DBL_MAX;
   for(int i=1;i<=20;i++)
     {
      h20=MathMax(h20,iHigh(_Symbol,PERIOD_CURRENT,i));
      l20=MathMin(l20,iLow (_Symbol,PERIOD_CURRENT,i));
     }
   TUTTO_PHASE  phase=g_phase.Det(cs,ss,g_mtf);
   AuthZoneData auth =g_auth.Analyze(price,h20,l20);
   EnergySnapshot es =g_energy.Calc(cs,ss,phase,auth,g_mtf);

   if(nb) CheckPhaseTransition(phase,es);

   // BLOCK-B: シグナル検出 (nbのみ)
   if(nb&&!g_signal.active&&!g_signal.pending)
     {
      DetectSetup(es,auth,g_signal);          // SETUP: AUTH+RELのみ判定
      DetectBuySell(es,ss,auth,g_signal,rates_total); // DETECT: SWEEP+RQ含む
     }

   // BLOCK-C: 価格監視 (毎Tick)
   MonitorTPSL(g_signal);

   // BLOCK-D: 構造監視 (nbのみ)
   if(nb) MonitorStructure(g_signal,auth,es);

   // Dashboard (ChartRedrawはnb時のみ)
   g_dash.Render(es,cs,ss,auth,g_signal,nb);

   return rates_total;
  }

//+------------------------------------------------------------------+
//  OnDeinit
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_mtf.Deinit();
   g_comp.Deinit();
   g_sweep.Deinit();
   g_phase.Deinit();
   g_energy.Deinit();
   g_dash.Deinit();
   DeleteSignalObjects();
   ObjectsDeleteAll(0,DASH_PFX);
  }
//+------------------------------------------------------------------+
