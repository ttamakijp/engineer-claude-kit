# pricing.psd1
# Concept pricing per 1M tokens, used by scripts/usage-insights.ps1 to turn raw
# token counts into relative cost insights. These are APPROXIMATE figures kept
# deliberately rough: web confirmation of current Bedrock / Anthropic list prices
# is pending, so the numbers below are for RELATIVE comparison only (which model /
# which cache mode dominates spend), never for billing reconciliation.
#
# ASCII only. See docs/adr/0014-usage-insights.md.
@{
    Sonnet = @{ input = 3.0;  output = 15.0; cache_write_5m = 3.75;  cache_write_1h = 6.0;  cache_read = 0.30 }
    Haiku  = @{ input = 1.0;  output = 5.0;  cache_write_5m = 1.25;  cache_write_1h = 2.0;  cache_read = 0.10 }
    Opus   = @{ input = 15.0; output = 75.0; cache_write_5m = 18.75; cache_write_1h = 30.0; cache_read = 1.50 }
    Note   = "Concept pricing per M tokens. Web confirmation pending. Used for relative insights only."
}
