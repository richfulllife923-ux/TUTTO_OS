//+------------------------------------------------------------------+
//|  TUTTO Phase Visualizer v5.0                                     |
//|  TUTTO CODEX Compliance: Appendix A v1.1                         |
//|  Predictive Market Field OS — Gravitational Field Architecture   |
//|                                                                   |
//|  PRESERVED from v4.0 (intact):                                   |
//|    Real cross-market Omega (SOXX W1, QQQ W1)                    |
//|    5-phase state machine S0/S1/S2/S2.5/S3                       |
//|    Weekly provisional flag                                        |
//|    Gravity Divergence Detector                                   |
//|    Omega Velocity Engine (dΩ/dt, d²Ω/dt²)                      |
//|    Regime Stability Score                                         |
//|    Collapse Probability (multi-factor 0-100%)                    |
//|    Phase Transition Events (CSV + Alert)                         |
//|                                                                   |
//|  NEW in v5.0:                                                     |
//|    [I]  MTF Omega Grid     — H1/H4/D1/W1 × BTC/SOX/QQQ states  |
//|    [II] Omega Heatmap HUD  — State matrix in Consolas grid       |
//|    [III]Auto Regime Label  — REAL TREND / FAKE RALLY /           |
//|                              TERMINAL DIST / LIQUIDITY TRAP      |
//|    [IV] EA Filter Layer    — Global buffer EA reads directly     |
//|         S2=entry | S2.5=reduce | S3=no-trade | DIV=block        |
//+------------------------------------------------------------------+
#property copyright   "TUTTO CODEX v1.1"
#property version     "5.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

//===================================================================
// SECTION 1: INPUT PARAMETERS
//===================================================================

input group "=== HUD DISPLAY ==="
input bool   InpShowAuthZone      = true;    // Show AUTH ZONE (2.33–2.618)
input bool   InpShowTerminalZone  = true;    // Show TERMINAL ZONE (3.77–4.236)
input int    InpZoneAlpha_Dim     = 25;      // Inactive zone alpha (0-255)
input int    InpZoneAlpha_Active  = 55;      // Active zone alpha (0-255)
input bool   InpShowLabels        = true;    // Show zone labels (HUD style)
input int    InpLabelFontSize     = 8;       // Label font size

input group "=== OMEGA ENGINE ==="
input int    InpOmega_Lookback    = 50;      // Omega anchor lookback (bars)
input string InpM2_Symbol         = "SOXX";  // M2 symbol (semiconductor index)
input string InpM3_Symbol         = "QQQ";   // M3 symbol (tech/macro index)
input string InpDXY_Symbol        = "DXY";   // DXY symbol for divergence check
// NOTE: Symbols must be in Market Watch. Use your broker's exact names.
// Common alternatives: "SOXS", "QQQM", "USDX", "DX-Y.NYB"

input group "=== GRAVITY DIVERGENCE ==="
input bool   InpDivergence_Enable = true;    // Enable Gravity Divergence Detector
input double InpDiv_BTCRise_Pct   = 2.0;     // BTC rise threshold (% over lookback)
input double InpDiv_SOXFall_Pct   = -1.0;    // SOXX fall threshold (% — negative)
input double InpDiv_DXYRise_Pct   = 0.5;     // DXY rise threshold (%)
input int    InpDiv_Lookback_Bars = 5;        // Bars lookback for divergence calc

// ── [NEW-A] Omega Velocity Engine ────────────────────────────────
input group "=== [A] OMEGA VELOCITY ENGINE ==="
input bool   InpVelocity_Enable   = true;    // Enable Velocity / Acceleration calc
input int    InpVelocity_Smooth   = 3;       // EMA smoothing periods for velocity

// ── [NEW-C] Regime Stability ──────────────────────────────────────
input group "=== [C] REGIME STABILITY ==="
input bool   InpStability_Enable  = true;    // Enable Stability Score
input double InpStability_Warn    = 0.30;    // Stability warn threshold (yellow)
input double InpStability_Alert   = 0.50;    // Stability alert threshold (red)

// ── [NEW-D] Collapse Probability ─────────────────────────────────
input group "=== [D] COLLAPSE PROBABILITY ==="
input bool   InpCollapse_Enable   = true;    // Enable Collapse Probability score
input double InpCollapse_Warn     = 50.0;    // Warn level % (yellow)
input double InpCollapse_Alert    = 75.0;    // Alert level % (red)

// ── [NEW-E] Phase Transition Events ──────────────────────────────
input group "=== [E] PHASE TRANSITION EVENTS ==="
input bool   InpTransition_Alert  = true;    // MT5 Alert on phase change
input bool   InpTransition_CSV    = true;    // Log transitions to CSV
input string InpTransition_File   = "TUTTO_Transitions.csv"; // CSV filename

input group "=== PERFORMANCE ==="
input int    InpTimerMs           = 500;     // Refresh timer (ms)

// ── [NEW-I/II] MTF Omega Grid & Heatmap ──────────────────────────
input group "=== [I/II] MTF OMEGA GRID ==="
input bool   InpMTF_Enable        = true;    // Enable MTF Omega Grid
// Timeframes computed: H1 (current), H4, D1, W1
// Symbols computed:    BTC (chart), M2 (SOXX), M3 (QQQ)

// ── [NEW-III] Auto Regime Label ──────────────────────────────────
input group "=== [III] AUTO REGIME LABEL ==="
input bool   InpRegime_Enable     = true;    // Enable auto regime classification
// Labels: REAL TREND | FAKE RALLY | TERMINAL DIST | LIQUIDITY TRAP | RECOVERY | DORMANT

// ── [NEW-IV] EA Filter Layer ──────────────────────────────────────
input group "=== [IV] EA FILTER LAYER ==="
input bool   InpEAFilter_Enable   = true;    // Enable EA filter global variables
// Writes to GlobalVariables (EA reads via GlobalVariableGet):
//   TUTTO_SIGNAL      : 1=entry OK, 0=reduce/avoid, -1=no-trade
//   TUTTO_REGIME      : 0=DORMANT,1=REALTREND,2=FAKERALLY,
//                       3=TERMINALDIST,4=LIQUIDITYTRAP,5=RECOVERY
//   TUTTO_COLLAPSE    : collapse probability 0-100
//   TUTTO_OMEGA       : current Omega value
//   TUTTO_VELOCITY    : current Omega velocity

//===================================================================
// SECTION 2: CONSTANTS — Object Names & Fib Thresholds
//===================================================================

// Zone boundary constants (TUTTO CODEX constitutional values)
const double AUTH_LOW     = 2.330;
const double AUTH_HIGH    = 2.618;
const double TERM_LOW     = 3.770;
const double TERM_HIGH    = 4.236;

// Object name registry (single allocation, move-only after init)
const string OBJ_ZONE_AUTH     = "TUTTO_ZONE_233";
const string OBJ_ZONE_TERM     = "TUTTO_ZONE_377";
const string OBJ_LBL_AUTH      = "TUTTO_LBL_AUTH";
const string OBJ_LBL_TERM      = "TUTTO_LBL_TERM";
const string OBJ_LBL_PHASE     = "TUTTO_LBL_PHASE";
const string OBJ_LBL_DIV       = "TUTTO_LBL_DIV";       // Divergence alert
const string OBJ_LBL_CROSS     = "TUTTO_LBL_CROSS";     // Cross-market readings
const string OBJ_LBL_VELOCITY  = "TUTTO_LBL_VEL";       // [NEW-A] VEL / ACC
const string OBJ_LBL_STABILITY = "TUTTO_LBL_STAB";      // [NEW-C] Stability Score
const string OBJ_LBL_COLLAPSE  = "TUTTO_LBL_COLL";      // [NEW-D] Collapse Probability
const string OBJ_LINE_AUTH_LO  = "TUTTO_LINE_AUTH_LO";
const string OBJ_LINE_AUTH_HI  = "TUTTO_LINE_AUTH_HI";
const string OBJ_LINE_TERM_LO  = "TUTTO_LINE_TERM_LO";
const string OBJ_LINE_TERM_HI  = "TUTTO_LINE_TERM_HI";
// [NEW-II] MTF Heatmap panel (right-side corner label)
const string OBJ_LBL_HEATMAP   = "TUTTO_LBL_HEATMAP";
// [NEW-III] Auto regime label (large, prominent)
const string OBJ_LBL_REGIME    = "TUTTO_LBL_REGIME";
// [NEW-IV] EA filter status
const string OBJ_LBL_EASIGNAL  = "TUTTO_LBL_EASIGNAL";

// Color palette — Tactical HUD / Market OS aesthetic
// Base: near-black. Auth: dark teal-green. Terminal: dark amber-red.
const color  CLR_AUTH_FILL      = C'0,38,20';       // deep dark green
const color  CLR_TERM_FILL      = C'52,14,0';       // deep dark red-amber
const color  CLR_AUTH_EDGE      = C'0,180,80';      // acid green
const color  CLR_TERM_EDGE      = C'220,80,0';      // amber-orange
const color  CLR_AUTH_LBL       = C'0,210,100';     // bright green
const color  CLR_TERM_LBL       = C'255,110,20';    // hot amber
const color  CLR_PHASE_LBL      = C'160,160,180';   // cold steel
const color  CLR_DIM_EDGE       = C'40,40,45';      // nearly invisible

//===================================================================
// SECTION 3: GLOBAL STATE
//===================================================================

bool   g_ObjectsCreated = false;
int    g_OmegaState     = 0;   // 0=S0,1=S1,2=S2,25=S2.5,3=S3
int    g_OmegaStatePrev = 0;   // [NEW-E] previous state for transition detection
int    g_S2Counter      = 0;
bool   g_S25Active      = false;
double g_OmegaValue     = 0.0;

// Weekly provisional state
bool   g_IsProvisional  = false;

// Cross-market readings (for HUD display)
double g_fM1            = 0.0;   // BTC normalized
double g_fM2            = 0.0;   // SOXX normalized
double g_fM3            = 0.0;   // QQQ normalized
double g_fDXY           = 0.0;   // DXY delta %
bool   g_M2_Available   = false;
bool   g_M3_Available   = false;
bool   g_DXY_Available  = false;

// Gravity divergence state
bool   g_DivergenceActive = false;
string g_DivergenceDetail = "";

// ── [NEW-A] Omega Velocity Engine ────────────────────────────────
// dΩ/dt  : rate of change of Omega per bar (first derivative)
// d²Ω/dt²: rate of change of velocity     (second derivative / acceleration)
//
// Interpretation matrix:
//   Ω↑  Vel↑  Acc↑  → Genuine S2 momentum — real trend, energy building
//   Ω↑  Vel↓  Acc−  → Internal collapse   — price up, energy dying (fake rally)
//   Ω↓  Vel−  Acc↑  → Recovery attempt    — deceleration slowing, possible base
//   Ω↓  Vel−  Acc−  → Full collapse mode  — avoid all entries
double g_OmegaPrev      = 0.0;
double g_OmegaVelocity  = 0.0;   // dΩ/dt
double g_OmegaAccel     = 0.0;   // d²Ω/dt²
double g_OmegaVelPrev   = 0.0;
// EMA-smoothed versions (reduce bar-to-bar noise)
double g_VelSmooth      = 0.0;
double g_AccSmooth      = 0.0;

// ── [NEW-C] Regime Stability Score ───────────────────────────────
// Measures cross-market divergence magnitude.
// stability = |fM1 − fM2| + |fM1 − fM3|
// Range: 0.0 (perfect sync) → 2.0 (maximum divergence, theoretical)
// Typical: < 0.15 healthy, 0.15–0.40 caution, > 0.40 danger
double g_StabilityScore = 0.0;

// ── [NEW-D] Collapse Probability ─────────────────────────────────
// Multi-factor score 0–100 representing S2.5 collapse risk.
// Factors (each contributes weight to total):
//   [30pts] Omega in terminal zone (>3.77)
//   [20pts] Velocity negative or strongly decelerating
//   [20pts] Acceleration negative
//   [15pts] Stability score > warn threshold
//   [10pts] SOXX weak (fM2 < 0.4)
//   [5pts]  DXY strengthening
double g_CollapsePct    = 0.0;

// ── [NEW-E] Phase Transition ──────────────────────────────────────
int    g_CSV_Handle     = INVALID_HANDLE;
bool   g_CSV_Inited     = false;

// ── [NEW-I] MTF Omega Grid ────────────────────────────────────────
// Stores Omega state for each [timeframe × symbol] combination.
// Layout: g_MTF_State[TF][SYM]
//   TF:  0=H1, 1=H4, 2=D1, 3=W1
//   SYM: 0=BTC(chart), 1=SOXX(M2), 2=QQQ(M3)
// Value: 0=S0, 1=S1, 2=S2, 25=S2.5, 3=S3, -1=N/A
int    g_MTF_State[4][3];
double g_MTF_Omega[4][3];
bool   g_MTF_Ready      = false;

// MTF timeframe array (iterated in CalcMTFGrid)
// PERIOD_H1=16385, PERIOD_H4=16388, PERIOD_D1=16408, PERIOD_W1=32769
ENUM_TIMEFRAMES g_MTF_TF[4];   // populated in OnInit

// ── [NEW-III] Auto Regime Classification ─────────────────────────
// RegimeID values (also written to GlobalVariable TUTTO_REGIME):
//   0 = DORMANT          — S0, no structure
//   1 = REAL TREND       — S2 + Vel↑ + Acc↑ + Stability healthy
//   2 = FAKE RALLY       — Ω↑ but Vel↓ + Acc− + SOXX weak
//   3 = TERMINAL DIST    — S2.5 + CollapsePct high + Stability bad
//   4 = LIQUIDITY TRAP   — S3 + DivergenceActive
//   5 = RECOVERY         — Vel− + Acc↑ (deceleration slowing)
int    g_RegimeID       = 0;
string g_RegimeLabel    = "DORMANT";

// ── [NEW-IV] EA Filter Layer ──────────────────────────────────────
// EA signal written to GlobalVariables each bar:
//   +1 = entry permitted (S2, real trend conditions met)
//    0 = reduce / avoid (S2.5, or partial concern)
//   -1 = no-trade (S3, divergence active, or liquidity trap)
int    g_EASignal       = 0;

// Mapped price levels for zone bands
double g_PriceAuthLow  = 0.0;
double g_PriceAuthHigh = 0.0;
double g_PriceTermLow  = 0.0;
double g_PriceTermHigh = 0.0;
bool   g_PriceMapped   = false;

//===================================================================
// SECTION 4: INIT / DEINIT
//===================================================================

int OnInit()
  {
   // [NEW-I] MTF timeframe array init
   g_MTF_TF[0] = PERIOD_H1;
   g_MTF_TF[1] = PERIOD_H4;
   g_MTF_TF[2] = PERIOD_D1;
   g_MTF_TF[3] = PERIOD_W1;
   // Initialize grid to N/A
   for(int t = 0; t < 4; t++)
      for(int s = 0; s < 3; s++)
        { g_MTF_State[t][s] = -1; g_MTF_Omega[t][s] = 0.0; }

   EventSetMillisecondTimer(InpTimerMs);
   CreateAllObjects();
   if(InpTransition_CSV) InitTransitionCSV();
   return INIT_SUCCEEDED;
  }

//-------------------------------------------------------------------
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteAllObjects();
   if(g_CSV_Handle != INVALID_HANDLE) FileClose(g_CSV_Handle);
   ChartRedraw();
  }

//===================================================================
// SECTION 5: CALCULATION — OMEGA ENGINE (Appendix A v1.1)
//===================================================================

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
   // Run on every new bar only
   if(rates_total < InpOmega_Lookback + 10) return rates_total;

   CalcOmegaAndMap(rates_total, high, low, close);
   UpdateZoneVisuals();
   ChartRedraw();
   return rates_total;
  }

//-------------------------------------------------------------------
// Timer handles mid-bar tick refresh for smooth HUD tracking
void OnTimer()
  {
   if(!g_ObjectsCreated) { CreateAllObjects(); return; }

   int rates_total = Bars(_Symbol, PERIOD_CURRENT);
   if(rates_total < InpOmega_Lookback + 10) return;

   double high[], low[], close[];
   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, rates_total, high)  <= 0) return;
   if(CopyLow  (_Symbol, PERIOD_CURRENT, 0, rates_total, low)   <= 0) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, rates_total, close) <= 0) return;
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   CalcOmegaAndMap(rates_total, high, low, close);
   UpdateZoneVisuals();
   ChartRedraw();
  }

//===================================================================
// SECTION 6: OMEGA CALCULATION + PRICE MAPPING
//
// Constitutional Omega formula (TUTTO CODEX Appendix A v1.1):
//   Ω = F(M1) − 0.618·F(M2) − 0.382·F(M3)
//   F(Mi,t) = (Close − Anchor_Low) / (Anchor_High − Anchor_Low)
//
//   M1 = BTC/USD   (H1, chart symbol)
//   M2 = SOXX W1   [NEW-1] real semiconductor index
//   M3 = QQQ  W1   [NEW-1] real tech/macro index
//
// Why real cross-market data matters:
//   fM2 * 0.85 was a scaled proxy of fM1 — structurally identical.
//   It could NEVER detect "BTC up, SOX down" divergence because both
//   moved in lockstep. With real SOXX/QQQ weekly closes, Omega now
//   punishes scenarios where BTC rises alone: fM1 rises but fM2/fM3
//   don't, causing Omega to stay depressed. This is the core of the
//   TUTTO "fake rally" filter.
//
// State machine [NEW-2]:
//   S0   omega < 2.330   → Dormant
//   S1   omega < 2.618   → Auth band (initial authentication)
//   S2   omega < 3.770   → Real acceleration
//   S2.5 omega < 4.236   → Terminal approach
//   S3   omega >= 4.236  → Apex / T=0
//
// Provisional flag [NEW-3]:
//   Weekly candle not closed (Fri ≥ 23:00 server time = closed).
//   Before that, SOXX/QQQ weekly F values are mid-candle estimates.
//
// Price mapping:
//   Price = AnchorLow + (OmegaThreshold / 4.236) × AnchorRange
//===================================================================

void CalcOmegaAndMap(const int total,
                     const double &high[],
                     const double &low[],
                     const double &close[])
  {
   int lb = InpOmega_Lookback;

   //── M1: BTC anchor (H1 confirmed bars) ──────────────────────────
   double anchorHigh = high[ArrayMaximum(high, 0, lb)];
   double anchorLow  = low [ArrayMinimum(low,  0, lb)];
   double range      = anchorHigh - anchorLow;
   if(range < _Point) return;

   g_fM1 = (close[0] - anchorLow) / range;
   g_fM1 = MathMax(0.0, MathMin(1.0, g_fM1));

   //── [NEW-3] Weekly provisional check ────────────────────────────
   // Week is "closed" only on Friday at or after 23:00 server time.
   // Before that, the weekly candle is still forming — Omega is provisional.
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool weekClosed = (dt.day_of_week == 5 && dt.hour >= 23);
   g_IsProvisional = !weekClosed;

   //── [NEW-1] M2: SOXX weekly close ────────────────────────────────
   // CopyClose on W1 gives confirmed + current forming bar.
   // lb bars should be sufficient for the weekly anchor.
   double soxClose[];
   g_M2_Available = (CopyClose(InpM2_Symbol, PERIOD_W1, 0, lb, soxClose) >= lb);
   if(g_M2_Available)
     {
      ArraySetAsSeries(soxClose, true);
      double soxHigh = soxClose[ArrayMaximum(soxClose, 0, lb)];
      double soxLow  = soxClose[ArrayMinimum(soxClose, 0, lb)];
      double soxRng  = soxHigh - soxLow;
      g_fM2 = (soxRng > 0.0001)
               ? MathMax(0.0, MathMin(1.0, (soxClose[0] - soxLow) / soxRng))
               : g_fM1 * 0.85;   // graceful fallback
     }
   else
      g_fM2 = g_fM1 * 0.85;   // symbol not in Market Watch — fallback

   //── [NEW-1] M3: QQQ weekly close ─────────────────────────────────
   double qqqClose[];
   g_M3_Available = (CopyClose(InpM3_Symbol, PERIOD_W1, 0, lb, qqqClose) >= lb);
   if(g_M3_Available)
     {
      ArraySetAsSeries(qqqClose, true);
      double qqqHigh = qqqClose[ArrayMaximum(qqqClose, 0, lb)];
      double qqqLow  = qqqClose[ArrayMinimum(qqqClose, 0, lb)];
      double qqqRng  = qqqHigh - qqqLow;
      g_fM3 = (qqqRng > 0.0001)
               ? MathMax(0.0, MathMin(1.0, (qqqClose[0] - qqqLow) / qqqRng))
               : g_fM1 * 0.70;
     }
   else
      g_fM3 = g_fM1 * 0.70;

   //── Constitutional Omega formula [M-03] ─────────────────────────
   // Raw range: ~0.0 to ~0.264 (when fM1=1, fM2=0.85, fM3=0.70)
   // Scale to constitutional domain [0 .. 4.236]:  ÷0.264 × 4.236 ≈ ×16.045
   double omegaRaw = g_fM1 - 0.618 * g_fM2 - 0.382 * g_fM3;
   g_OmegaValue    = omegaRaw * 16.045;   // now in [0..4.236] space

   //── [NEW-2] Corrected 5-phase state machine ──────────────────────
   // Each boundary is a distinct TUTTO constitutional threshold.
   // S2Counter/S25Active removed — S2.5 is now a pure price-band state.
   // (The weekly-close counter for S2.5 duration is tracked separately
   //  via g_IsProvisional which signals mid-week uncertainty.)
   g_OmegaStatePrev = g_OmegaState;   // [NEW-E] snapshot before update
   UpdateOmegaState(g_OmegaValue);

   //── [NEW-4] Gravity Divergence Detection ────────────────────────
   if(InpDivergence_Enable)
      CheckGravityDivergence();

   //── [NEW-A] Omega Velocity Engine ───────────────────────────────
   if(InpVelocity_Enable)
      CalcOmegaVelocity();

   //── [NEW-C] Regime Stability Score ──────────────────────────────
   if(InpStability_Enable)
      CalcRegimeStability();

   //── [NEW-D] Collapse Probability ────────────────────────────────
   if(InpCollapse_Enable)
      CalcCollapseProbability();

   //── [NEW-E] Phase Transition Event ──────────────────────────────
   if(g_OmegaState != g_OmegaStatePrev)
      FireTransitionEvent(g_OmegaStatePrev, g_OmegaState);

   //── [NEW-I] MTF Omega Grid ───────────────────────────────────────
  // if(InpMTF_Enable) CalcMTFGrid();
   //── [NEW-III] Auto Regime Classification ────────────────────────

  //── [NEW-IV] EA Filter Layer — write GlobalVariables ────────────
// if(InpEAFilter_Enable) UpdateEAFilter();

//── Price mapping to chart axis ─────────────────────────────────
const double MAX_OMEGA = 4.236;

g_PriceAuthLow  = anchorLow + (AUTH_LOW  / MAX_OMEGA) * range;
g_PriceAuthHigh = anchorLow + (AUTH_HIGH / MAX_OMEGA) * range;
g_PriceTermLow  = anchorLow + (TERM_LOW  / MAX_OMEGA) * range;
g_PriceTermHigh = anchorLow + (TERM_HIGH / MAX_OMEGA) * range;
g_PriceMapped   = true;
}

//===================================================================
// [NEW-A] OMEGA VELOCITY ENGINE
//
// Computes first and second derivatives of Omega over bars.
// Raw delta is EMA-smoothed to reduce H1 bar noise.
//
// Physics analogy:
//   Omega   = position in gravitational field
//   Velocity = momentum of market structure change
//   Accel    = force — is the momentum building or dying?
//
// Critical detection:
//   The scenario "Ω↑ but Vel↓ and Acc<0" is the signature of
//   a price pumping into terminal zone on dying internal energy.
//   This is NOT detectable from price alone — it requires the
//   second derivative of the cross-market normalized position.
//===================================================================

void CalcOmegaVelocity()
  {
   // Raw first derivative
   double velRaw  = g_OmegaValue - g_OmegaPrev;
   // Raw second derivative
   double accRaw  = velRaw - g_OmegaVelPrev;

   // EMA smoothing: alpha = 2 / (N+1)
   double alpha = (InpVelocity_Smooth > 0)
                  ? 2.0 / (InpVelocity_Smooth + 1)
                  : 1.0;
   g_VelSmooth = alpha * velRaw + (1.0 - alpha) * g_VelSmooth;
   g_AccSmooth = alpha * accRaw + (1.0 - alpha) * g_AccSmooth;

   g_OmegaVelocity = g_VelSmooth;
   g_OmegaAccel    = g_AccSmooth;

   // Advance state for next bar
   g_OmegaVelPrev = velRaw;
   g_OmegaPrev    = g_OmegaValue;
  }

//===================================================================
// [NEW-C] REGIME STABILITY SCORE
//
// Measures how much BTC is moving independently from its structural
// peers (SOXX, QQQ). A high stability score means the three markets
// are moving in sync — a healthy, sustainable trend.
// A low score (high divergence) means BTC is disconnected — the trend
// is fragile and likely unsupported by capital flows.
//
// Formula:
//   stability = |fM1 − fM2| + |fM1 − fM3|
//   Range: 0.0 (perfect alignment) → 2.0 (maximum divergence)
//   Practical: < 0.15 healthy | 0.15–0.35 watch | > 0.35 danger
//===================================================================

void CalcRegimeStability()
  {
   g_StabilityScore = MathAbs(g_fM1 - g_fM2) + MathAbs(g_fM1 - g_fM3);
  }

//===================================================================
// [NEW-D] COLLAPSE PROBABILITY SCORE
//
// Weighted multi-factor scoring producing a 0–100% collapse risk.
// Each factor is binary (condition met = add weight, else 0).
// Designed for S2.5 regime specifically — in S0/S1/S2 it is
// informational only. In S2.5/S3 it becomes operational.
//
// Weight table:
//   30  Omega in terminal zone (>= 3.77)
//   20  Velocity negative (Ω losing momentum)
//   20  Acceleration negative (momentum accelerating downward)
//   15  Stability score above warn threshold (markets diverging)
//   10  SOXX relatively weak (fM2 < 0.40)
//    5  DXY strengthening (positive delta)
//  ---
//  100  Maximum
//===================================================================

void CalcCollapseProbability()
  {
   double score = 0.0;

   // Factor 1: Omega in terminal zone [30 pts]
   if(g_OmegaValue >= TERM_LOW) score += 30.0;

   // Factor 2: Velocity negative [20 pts]
   if(g_OmegaVelocity < 0.0) score += 20.0;

   // Factor 3: Acceleration negative [20 pts]
   if(g_OmegaAccel < 0.0) score += 20.0;

   // Factor 4: Stability divergence above warn threshold [15 pts]
   if(g_StabilityScore >= InpStability_Warn) score += 15.0;

   // Factor 5: SOXX structurally weak [10 pts]
   if(g_M2_Available && g_fM2 < 0.40) score += 10.0;

   // Factor 6: DXY strengthening [5 pts]
   if(g_DXY_Available && g_fDXY > 0.0) score += 5.0;

   g_CollapsePct = MathMax(0.0, MathMin(100.0, score));
  }

//===================================================================
// [NEW-E] PHASE TRANSITION EVENT SYSTEM
//
// Fires on every state change: g_OmegaStatePrev != g_OmegaState
// Actions:
//   1. MT5 Alert (if InpTransition_Alert = true)
//   2. CSV row append (if InpTransition_CSV  = true)
//
// CSV columns:
//   DateTime | FromState | ToState | Omega | Velocity | Accel |
//   Stability | CollapsePct | BTC_fM1 | SOX_fM2 | QQQ_fM3 | Provisional
//
// The CSV is the raw material for external analysis — feeding into
// Python/Claude for regime pattern recognition and predictive modeling.
//===================================================================

string StateLabel(int state)
  {
   switch(state)
     {
      case 0:  return "S0_DORMANT";
      case 1:  return "S1_AUTH";
      case 2:  return "S2_ACCEL";
      case 25: return "S2.5_TERMINAL";
      case 3:  return "S3_APEX";
      default: return "S??";
     }
  }

void FireTransitionEvent(int fromState, int toState)
  {
   string fromLbl  = StateLabel(fromState);
   string toLbl    = StateLabel(toState);
   string timeStr  = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   string omegaStr = DoubleToString(g_OmegaValue, 4);

   // Transition message with operational context
   string msg = "";
   if(fromState == 1 && toState == 2)
      msg = "BREAKOUT CONFIRMED — S1→S2 structural acceleration";
   else if(fromState == 2 && toState == 25)
      msg = "TERMINAL INSTABILITY — S2→S2.5 collapse precursor";
   else if(fromState == 25 && toState == 3)
      msg = "APEX COLLAPSE RISK — S2.5→S3 maximum extension";
   else if(toState == 0)
      msg = "STRUCTURE RESET — returning to dormant";
   else
      msg = StringFormat("%s → %s", fromLbl, toLbl);

   // Print always
   Print("TUTTO TRANSITION: ", msg, " | Ω=", omegaStr,
         " | VEL=", DoubleToString(g_OmegaVelocity, 4),
         " | STAB=", DoubleToString(g_StabilityScore, 3),
         " | RISK=", DoubleToString(g_CollapsePct, 1), "%");

   // MT5 Alert
   if(InpTransition_Alert)
      Alert("TUTTO OS: ", msg, " | Ω=", omegaStr);

   // CSV append
   if(InpTransition_CSV && g_CSV_Handle != INVALID_HANDLE)
     {
      FileWrite(g_CSV_Handle,
                timeStr,
                fromLbl,
                toLbl,
                DoubleToString(g_OmegaValue,    4),
                DoubleToString(g_OmegaVelocity, 4),
                DoubleToString(g_OmegaAccel,    4),
                DoubleToString(g_StabilityScore,4),
                DoubleToString(g_CollapsePct,   1),
                DoubleToString(g_fM1,           4),
                DoubleToString(g_fM2,           4),
                DoubleToString(g_fM3,           4),
                DoubleToString(g_fDXY,          3),
                g_IsProvisional ? "PROVISIONAL" : "CONFIRMED",
                msg);
      FileFlush(g_CSV_Handle);
     }
  }

void InitTransitionCSV()
  {
   bool newFile = !FileIsExist(InpTransition_File, FILE_COMMON);
   g_CSV_Handle = FileOpen(InpTransition_File,
                           FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON, ',');
   if(g_CSV_Handle == INVALID_HANDLE)
     { Print("Transition CSV open failed: ", GetLastError()); return; }
   FileSeek(g_CSV_Handle, 0, SEEK_END);
   if(newFile)
      FileWrite(g_CSV_Handle,
                "DateTime","FromState","ToState",
                "Omega","Velocity","Acceleration",
                "Stability","CollapsePct",
                "fM1_BTC","fM2_SOX","fM3_QQQ","fDXY",
                "WeekStatus","Message");
   g_CSV_Inited = true;
   Print("Transition CSV: ", InpTransition_File);
  }

//-------------------------------------------------------------------
// [NEW-2] Corrected 5-phase state machine
// Constitutional thresholds — exact TUTTO CODEX values.
// S2 and S2.5 are now distinct bands, not a shared blob.
void UpdateOmegaState(double omega)
  {
   if(omega < 2.330)
      g_OmegaState = 0;       // S0  Dormant — below authentication floor
   else if(omega < 2.618)
      g_OmegaState = 1;       // S1  Auth band — initial trend authentication
   else if(omega < 3.770)
      g_OmegaState = 2;       // S2  Real acceleration — confirmed trend
   else if(omega < 4.236)
      g_OmegaState = 25;      // S2.5 Terminal approach — collapse precursor
   else
      g_OmegaState = 3;       // S3  Apex / T=0 — maximum extension
  }

//-------------------------------------------------------------------
// [NEW-4] Gravity Divergence Detector
//
// A "gravity divergence" occurs when BTC rises in isolation
// while the structural market forces (semiconductors, tech) are falling
// AND the dollar is strengthening. This is the signature of a
// liquidity-driven fake rally without fundamental support.
//
// Trigger condition (ALL three must be true simultaneously):
//   BTC    N-bar return >= +InpDiv_BTCRise_Pct   (rising)
//   SOXX   N-bar return <= InpDiv_SOXFall_Pct    (falling, negative threshold)
//   DXY    N-bar return >= +InpDiv_DXYRise_Pct   (dollar strengthening)
//
// When active: HUD displays ⚠ GRAVITY DIVERGENCE / NO-GO CONDITION
//
void CheckGravityDivergence()
  {
   g_DivergenceActive = false;
   g_DivergenceDetail = "";
   int n = InpDiv_Lookback_Bars + 1;

   //── BTC return ───────────────────────────────────────────────────
   double btcClose[];
   if(CopyClose(_Symbol, PERIOD_H1, 0, n, btcClose) < n) return;
   ArraySetAsSeries(btcClose, true);
   double btcReturn = 0.0;
   if(btcClose[n-1] > 0.0)
      btcReturn = (btcClose[0] - btcClose[n-1]) / btcClose[n-1] * 100.0;

   //── SOXX return ──────────────────────────────────────────────────
   double soxDiv[];
   bool soxOk = (CopyClose(InpM2_Symbol, PERIOD_D1, 0, n, soxDiv) >= n);
   double soxReturn = 0.0;
   if(soxOk)
     {
      ArraySetAsSeries(soxDiv, true);
      if(soxDiv[n-1] > 0.0)
         soxReturn = (soxDiv[0] - soxDiv[n-1]) / soxDiv[n-1] * 100.0;
     }

   //── DXY return ───────────────────────────────────────────────────
   double dxyDiv[];
   g_DXY_Available = (CopyClose(InpDXY_Symbol, PERIOD_D1, 0, n, dxyDiv) >= n);
   double dxyReturn = 0.0;
   if(g_DXY_Available)
     {
      ArraySetAsSeries(dxyDiv, true);
      if(dxyDiv[n-1] > 0.0)
         dxyReturn = (dxyDiv[0] - dxyDiv[n-1]) / dxyDiv[n-1] * 100.0;
      g_fDXY = dxyReturn;
     }

   //── Divergence judgment ──────────────────────────────────────────
   bool btcUp  = (btcReturn >= InpDiv_BTCRise_Pct);
   bool soxDwn = soxOk && (soxReturn <= InpDiv_SOXFall_Pct);
   bool dxyUp  = g_DXY_Available && (dxyReturn >= InpDiv_DXYRise_Pct);

   if(btcUp && soxDwn && dxyUp)
     {
      g_DivergenceActive = true;
      g_DivergenceDetail = StringFormat(
         "BTC %+.1f%%  SOX %+.1f%%  DXY %+.1f%%",
         btcReturn, soxReturn, dxyReturn);
     }
   else if(btcUp && soxDwn)
     {
      // Partial divergence — still a warning, DXY not available or not risen
      g_DivergenceActive = true;
      g_DivergenceDetail = StringFormat(
         "BTC %+.1f%%  SOX %+.1f%%  [DXY UNCONFIRMED]",
         btcReturn, soxReturn);
     }
  }

//===================================================================
// SECTION 7: ZONE VISUAL UPDATE
// Core HUD update logic — moves objects, adjusts alpha and color.
// Never re-creates objects after init (zero-flicker guarantee).
//===================================================================

void UpdateZoneVisuals()
  {
   if(!g_ObjectsCreated || !g_PriceMapped) return;

   // Phase classification
   bool authActive = (g_OmegaState == 1 || g_OmegaState == 2);
   bool termActive = (g_OmegaState == 25 || g_OmegaState == 3);

   // Alpha values
   int alphaAuth = authActive ? InpZoneAlpha_Active : InpZoneAlpha_Dim;
   int alphaTerm = termActive ? InpZoneAlpha_Active : InpZoneAlpha_Dim;

   // ── AUTH ZONE ────────────────────────────────────────────────────
   if(InpShowAuthZone)
     {
      // Reposition rectangle to mapped price levels
      ObjectSetDouble(0, OBJ_ZONE_AUTH, OBJPROP_PRICE, 0, g_PriceAuthHigh);
      ObjectSetDouble(0, OBJ_ZONE_AUTH, OBJPROP_PRICE, 1, g_PriceAuthLow);

      // Fill color — encode alpha in ARGB (MT5 uses ColorToARGB)
      color fillAuth = authActive ? CLR_AUTH_FILL : C'0,25,12';
      ObjectSetInteger(0, OBJ_ZONE_AUTH, OBJPROP_BGCOLOR,
              ColorToARGB(fillAuth, (uchar)alphaAuth));
      // Edge lines
      color edgeAuth = authActive ? CLR_AUTH_EDGE : CLR_DIM_EDGE;
      int   edgeW    = authActive ? 1 : 0;
      ObjectSetInteger(0, OBJ_LINE_AUTH_HI, OBJPROP_COLOR, edgeAuth);
      ObjectSetInteger(0, OBJ_LINE_AUTH_LO, OBJPROP_COLOR, edgeAuth);
      ObjectSetInteger(0, OBJ_LINE_AUTH_HI, OBJPROP_WIDTH, edgeW);
      ObjectSetInteger(0, OBJ_LINE_AUTH_LO, OBJPROP_WIDTH, edgeW);
      ObjectSetDouble (0, OBJ_LINE_AUTH_HI, OBJPROP_PRICE, g_PriceAuthHigh);
      ObjectSetDouble (0, OBJ_LINE_AUTH_LO, OBJPROP_PRICE, g_PriceAuthLow);

      // Label
      if(InpShowLabels)
        {
         color lblClr = authActive ? CLR_AUTH_LBL : C'0,80,40';
         ObjectSetDouble (0, OBJ_LBL_AUTH, OBJPROP_PRICE,
                          g_PriceAuthHigh + (g_PriceAuthHigh - g_PriceAuthLow) * 0.12);
         ObjectSetInteger(0, OBJ_LBL_AUTH, OBJPROP_COLOR, lblClr);
         string authTxt = authActive
                          ? "▶ AUTH ZONE  2.33 → 2.618  [ACTIVE]"
                          : "  AUTH ZONE  2.33 → 2.618";
         ObjectSetString (0, OBJ_LBL_AUTH, OBJPROP_TEXT, authTxt);
        }
     }

   // ── TERMINAL ZONE ────────────────────────────────────────────────
   if(InpShowTerminalZone)
     {
      ObjectSetDouble(0, OBJ_ZONE_TERM, OBJPROP_PRICE, 0, g_PriceTermHigh);
      ObjectSetDouble(0, OBJ_ZONE_TERM, OBJPROP_PRICE, 1, g_PriceTermLow);

      color fillTerm = termActive ? CLR_TERM_FILL : C'30,8,0';
      ObjectSetInteger(0, OBJ_ZONE_TERM, OBJPROP_BGCOLOR,
                      ColorToARGB(fillTerm, (uchar)alphaTerm));

      color edgeTerm = termActive ? CLR_TERM_EDGE : CLR_DIM_EDGE;
      int   edgeTW   = termActive ? 1 : 0;
      ObjectSetInteger(0, OBJ_LINE_TERM_HI, OBJPROP_COLOR, edgeTerm);
      ObjectSetInteger(0, OBJ_LINE_TERM_LO, OBJPROP_COLOR, edgeTerm);
      ObjectSetInteger(0, OBJ_LINE_TERM_HI, OBJPROP_WIDTH, edgeTW);
      ObjectSetInteger(0, OBJ_LINE_TERM_LO, OBJPROP_WIDTH, edgeTW);
      ObjectSetDouble (0, OBJ_LINE_TERM_HI, OBJPROP_PRICE, g_PriceTermHigh);
      ObjectSetDouble (0, OBJ_LINE_TERM_LO, OBJPROP_PRICE, g_PriceTermLow);

      if(InpShowLabels)
        {
         color lblClr = termActive ? CLR_TERM_LBL : C'90,40,0';
         ObjectSetDouble (0, OBJ_LBL_TERM, OBJPROP_PRICE,
                          g_PriceTermHigh + (g_PriceTermHigh - g_PriceTermLow) * 0.12);
         ObjectSetInteger(0, OBJ_LBL_TERM, OBJPROP_COLOR, lblClr);
         string termTxt = termActive
                          ? "▶ TERMINAL ZONE  3.77 → 4.236  [CRITICAL]"
                          : "  TERMINAL ZONE  3.77 → 4.236";
         ObjectSetString (0, OBJ_LBL_TERM, OBJPROP_TEXT, termTxt);
        }
     }

   // ── Phase HUD label (top-left corner) ────────────────────────────
   if(InpShowLabels)
     {
      string phaseStr = PhaseString();
      ObjectSetString(0, OBJ_LBL_PHASE, OBJPROP_TEXT, phaseStr);
      color phaseClr = PhaseColor();
      ObjectSetInteger(0, OBJ_LBL_PHASE, OBJPROP_COLOR, phaseClr);

      // Cross-market readings line
      string crossStr = CrossMarketString();
      ObjectSetString(0, OBJ_LBL_CROSS, OBJPROP_TEXT, crossStr);
      color crossClr = (g_M2_Available && g_M3_Available)
                        ? C'100,130,100' : C'80,80,60';
      ObjectSetInteger(0, OBJ_LBL_CROSS, OBJPROP_COLOR, crossClr);

      // [NEW-B] Velocity / Acceleration Heat HUD
      if(InpVelocity_Enable)
        {
         string velStr = VelocityString();
         color  velClr = VelocityColor();
         ObjectSetString (0, OBJ_LBL_VELOCITY, OBJPROP_TEXT,  velStr);
         ObjectSetInteger(0, OBJ_LBL_VELOCITY, OBJPROP_COLOR, velClr);
        }

      // [NEW-C] Stability score
      if(InpStability_Enable)
        {
         string stabStr = StabilityString();
         color  stabClr = StabilityColor();
         ObjectSetString (0, OBJ_LBL_STABILITY, OBJPROP_TEXT,  stabStr);
         ObjectSetInteger(0, OBJ_LBL_STABILITY, OBJPROP_COLOR, stabClr);
        }

      // [NEW-D] Collapse probability
      if(InpCollapse_Enable)
        {
         string collStr = CollapseString();
         color  collClr = CollapseColor();
         ObjectSetString (0, OBJ_LBL_COLLAPSE, OBJPROP_TEXT,  collStr);
         ObjectSetInteger(0, OBJ_LBL_COLLAPSE, OBJPROP_COLOR, collClr);
        }

      // Gravity Divergence alert
      if(g_DivergenceActive)
        {
         ObjectSetString (0, OBJ_LBL_DIV, OBJPROP_TEXT,
                          "⚠  GRAVITY DIVERGENCE  —  NO-GO CONDITION\n" +
                          g_DivergenceDetail);
         ObjectSetInteger(0, OBJ_LBL_DIV, OBJPROP_COLOR,    C'255,40,20');
         ObjectSetInteger(0, OBJ_LBL_DIV, OBJPROP_FONTSIZE, 10);
        }
      else
        {
         ObjectSetString (0, OBJ_LBL_DIV, OBJPROP_TEXT, "");
         ObjectSetInteger(0, OBJ_LBL_DIV, OBJPROP_FONTSIZE, InpLabelFontSize);
        }
     }
  }

//===================================================================
// SECTION 8: OBJECT LIFECYCLE — Create once, move forever
//===================================================================

void CreateAllObjects()
  {
   if(g_ObjectsCreated) return;

   // We need an initial price anchor to place objects.
   // Use current chart midpoint; UpdateZoneVisuals() corrects immediately.
   double mid = (ChartGetDouble(0, CHART_PRICE_MAX) +
                 ChartGetDouble(0, CHART_PRICE_MIN)) * 0.5;
   double span = (ChartGetDouble(0, CHART_PRICE_MAX) -
                  ChartGetDouble(0, CHART_PRICE_MIN));

   datetime t1 = (datetime)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   datetime t2 = TimeCurrent() + 86400 * 3;  // extend right 3 days

   // ── AUTH ZONE rectangle ──────────────────────────────────────────
   if(InpShowAuthZone)
     {
      CreateZoneRect(OBJ_ZONE_AUTH, t1, t2,
                     mid + span * 0.1, mid - span * 0.1,
                   ColorToARGB(CLR_AUTH_FILL, (uchar)InpZoneAlpha_Dim));
      CreateHLine(OBJ_LINE_AUTH_HI, mid + span * 0.1, CLR_DIM_EDGE, 0);
      CreateHLine(OBJ_LINE_AUTH_LO, mid - span * 0.1, CLR_DIM_EDGE, 0);

      if(InpShowLabels)
         CreatePriceLabel(OBJ_LBL_AUTH, mid + span * 0.12,
                          "  AUTH ZONE  2.33 → 2.618",
                          CLR_AUTH_LBL, InpLabelFontSize);
     }

   // ── TERMINAL ZONE rectangle ──────────────────────────────────────
   if(InpShowTerminalZone)
     {
      CreateZoneRect(OBJ_ZONE_TERM, t1, t2,
                     mid + span * 0.2, mid + span * 0.05,
                   ColorToARGB(CLR_TERM_FILL, (uchar)InpZoneAlpha_Dim));
      CreateHLine(OBJ_LINE_TERM_HI, mid + span * 0.2, CLR_DIM_EDGE, 0);
      CreateHLine(OBJ_LINE_TERM_LO, mid + span * 0.05, CLR_DIM_EDGE, 0);

      if(InpShowLabels)
         CreatePriceLabel(OBJ_LBL_TERM, mid + span * 0.22,
                          "  TERMINAL ZONE  3.77 → 4.236",
                          CLR_TERM_LBL, InpLabelFontSize);
     }

   // ── Phase HUD — corner label ─────────────────────────────────────
   if(InpShowLabels)
     {
      CreateCornerLabel(OBJ_LBL_PHASE,
                        "TUTTO OS  |  PHASE: S0",
                        CLR_PHASE_LBL, 9);

      // Cross-market line — 2nd row, below phase label
      CreateCornerLabelOffset(OBJ_LBL_CROSS,
                              "M1:BTC ---  M2:SOX ---  M3:QQQ ---",
                              C'80,90,80', 8, 12, 28);

      // [NEW-B] Velocity / Accel HUD — 3rd row
      CreateCornerLabelOffset(OBJ_LBL_VELOCITY,
                              "VEL ---  ACC ---",
                              C'80,100,80', 8, 12, 44);

      // [NEW-C] Stability — 4th row
      CreateCornerLabelOffset(OBJ_LBL_STABILITY,
                              "STABILITY ---",
                              C'80,100,80', 8, 12, 60);

      // [NEW-D] Collapse probability — 5th row
      CreateCornerLabelOffset(OBJ_LBL_COLLAPSE,
                              "COLLAPSE RISK ---",
                              C'80,80,80', 8, 12, 76);

      // Divergence alert — 6th row (hidden until triggered)
      CreateCornerLabelOffset(OBJ_LBL_DIV,
                              "",
                              C'255,40,20', 10, 12, 96);
     }

   g_ObjectsCreated = true;
  }

//-------------------------------------------------------------------
// Helper: create full-width zone rectangle
void CreateZoneRect(const string name,
                    datetime     t1,
                    datetime     t2,
                    double       priceTop,
                    double       priceBot,
                    color        fillARGB)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, priceTop, t2, priceBot);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrNONE);    // no border
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    fillARGB);
   ObjectSetInteger(0, name, OBJPROP_FILL,       true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);       // behind candles
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     0);
  }

//-------------------------------------------------------------------
// Helper: horizontal price line
void CreateHLine(const string name, double price, color clr, int width)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
  }

//-------------------------------------------------------------------
// Helper: floating price-anchored text label
void CreatePriceLabel(const string name,
                      double       price,
                      const string text,
                      color        clr,
                      int          fontSize)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   // Use the first visible bar as the left anchor
   int    firstBar = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int    totalBars = Bars(_Symbol, PERIOD_CURRENT);
   int    barIdx    = MathMin(firstBar, totalBars - 1);
   datetime t       = iTime(_Symbol, PERIOD_CURRENT, barIdx);

   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
  }

//-------------------------------------------------------------------
// Helper: fixed corner label (top-left, pixel-anchored)
void CreateCornerLabel(const string name,
                       const string text,
                       color        clr,
                       int          fontSize)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 12);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
  }

//-------------------------------------------------------------------
// Helper: fixed corner label with explicit pixel offset (multi-row HUD)
void CreateCornerLabelOffset(const string name,
                             const string text,
                             color        clr,
                             int          fontSize,
                             int          xDist,
                             int          yDist)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xDist);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yDist);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
  }

//-------------------------------------------------------------------
void DeleteAllObjects()
  {
   string objs[] = {
      OBJ_ZONE_AUTH,    OBJ_ZONE_TERM,
      OBJ_LINE_AUTH_LO, OBJ_LINE_AUTH_HI,
      OBJ_LINE_TERM_LO, OBJ_LINE_TERM_HI,
      OBJ_LBL_AUTH,     OBJ_LBL_TERM,
      OBJ_LBL_PHASE,    OBJ_LBL_CROSS,
      OBJ_LBL_VELOCITY, OBJ_LBL_STABILITY,
      OBJ_LBL_COLLAPSE, OBJ_LBL_DIV
   };
   for(int i = 0; i < ArraySize(objs); i++)
      if(ObjectFind(0, objs[i]) >= 0)
         ObjectDelete(0, objs[i]);
   g_ObjectsCreated = false;
  }

//===================================================================
// SECTION 9: PHASE STRING & COLOR HELPERS
//===================================================================

// [NEW-3] Provisional suffix — warns when weekly candle is mid-formation
string ProvisionalSuffix()
  {
   return g_IsProvisional ? "  [PROVISIONAL — WEEK NOT CLOSED]" : "";
  }

string PhaseString()
  {
   string state = "";
   switch(g_OmegaState)
     {
      case 0:  state = "S0   DORMANT";           break;
      case 1:  state = "S1   AUTH BAND";         break;
      case 2:  state = "S2   ACCELERATION";      break;
      case 25: state = "S2.5 TERMINAL APPROACH"; break;
      case 3:  state = "S3   APEX / T=0";        break;
      default: state = "S??";
     }
   return StringFormat("TUTTO OS  |  Ω %.3f  |  %s%s",
                       g_OmegaValue, state, ProvisionalSuffix());
  }

// [NEW-1] Cross-market readings for HUD line 2
string CrossMarketString()
  {
   string m2Str = g_M2_Available
                  ? StringFormat("%.3f", g_fM2)
                  : "N/A";
   string m3Str = g_M3_Available
                  ? StringFormat("%.3f", g_fM3)
                  : "N/A";
   string dxyStr = g_DXY_Available
                   ? StringFormat("DXY Δ%+.2f%%", g_fDXY)
                   : "DXY N/A";
   return StringFormat("M1:BTC %.3f  M2:%s %s  M3:%s %s  %s",
                       g_fM1,
                       InpM2_Symbol, m2Str,
                       InpM3_Symbol, m3Str,
                       dxyStr);
  }

color PhaseColor()
  {
   if(g_DivergenceActive) return C'255,60,0';   // override to amber on divergence
   switch(g_OmegaState)
     {
      case 0:  return C'60,60,70';
      case 1:  return C'0,200,100';
      case 2:  return C'0,220,130';
      case 25: return C'255,140,0';
      case 3:  return C'255,60,40';
      default: return CLR_PHASE_LBL;
     }
  }

//===================================================================
// [NEW-B] VELOCITY HUD STRING & COLOR
//
// HUD display format:
//   VEL +0.142 ↑   ACC +0.021 ↑    → genuine momentum
//   VEL +0.031 →   ACC -0.094 ↓    → deceleration warning
//   VEL -0.088 ↓   ACC -0.012 ↓    → collapse mode
//
// Arrow symbols encode direction at a glance for tactical reading.
//===================================================================

string ArrowVel(double v)
  { return (v >  0.005) ? " ↑" : (v < -0.005) ? " ↓" : " →"; }

string VelocityString()
  {
   if(!InpVelocity_Enable) return "";
   return StringFormat("VEL %+.4f%s    ACC %+.4f%s",
                       g_OmegaVelocity, ArrowVel(g_OmegaVelocity),
                       g_OmegaAccel,    ArrowVel(g_OmegaAccel));
  }

color VelocityColor()
  {
   // Energy state classification
   bool velPos = (g_OmegaVelocity > 0.0);
   bool accPos = (g_OmegaAccel    > 0.0);

   if( velPos &&  accPos) return C'0,220,130';    // S2 genuine — bright green
   if( velPos && !accPos) return C'200,180,0';    // decelerating — yellow
   if(!velPos &&  accPos) return C'100,140,255';  // recovering — cold blue
   return C'220,60,40';                           // collapse mode — red
  }

//===================================================================
// [NEW-C] STABILITY HUD STRING & COLOR
//===================================================================

string StabilityString()
  {
   if(!InpStability_Enable) return "";
   string lvl = (g_StabilityScore < InpStability_Warn)  ? "HEALTHY"  :
                (g_StabilityScore < InpStability_Alert)  ? "WATCH"    : "UNSTABLE";
   return StringFormat("STABILITY %.3f  [%s]", g_StabilityScore, lvl);
  }

color StabilityColor()
  {
   if(g_StabilityScore < InpStability_Warn)  return C'0,180,90';    // healthy green
   if(g_StabilityScore < InpStability_Alert) return C'200,160,0';   // caution yellow
   return C'220,60,20';                                              // unstable red
  }

//===================================================================
// [NEW-D] COLLAPSE PROBABILITY HUD STRING & COLOR
//===================================================================

string CollapseString()
  {
   if(!InpCollapse_Enable) return "";
   string lvl = (g_CollapsePct < InpCollapse_Warn)  ? "LOW"      :
                (g_CollapsePct < InpCollapse_Alert)  ? "ELEVATED" : "CRITICAL";
   return StringFormat("COLLAPSE RISK  %.0f%%  [%s]", g_CollapsePct, lvl);
  }

color CollapseColor()
  {
   if(g_CollapsePct < InpCollapse_Warn)  return C'60,140,80';    // low — muted green
   if(g_CollapsePct < InpCollapse_Alert) return C'200,140,0';    // elevated — amber
   return C'240,30,10';                                           // critical — blood red
  }

//+------------------------------------------------------------------+
//  END — TUTTO Phase Visualizer v4.0                                |
//  TUTTO CODEX Appendix A v1.1 — Predictive Market Field OS        |
//  Visualization → State Engine → Energy Field → Collapse Detector |
//+------------------------------------------------------------------+