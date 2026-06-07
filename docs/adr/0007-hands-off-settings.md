---
status: Accepted
date: 2026-06-07
deciders: [Tetsuya]
tags: [settings, backend, hands-off, responsibility-separation]
---

# ADR-0007: Hands-off settings.json policy

> This ADR was promoted from Proposed to Accepted in this PR. Implementation is included.

## Context

螳滓ｩ滓､懆ｨｼ (2026-06-07) 縺ｧ莉･荳九・驥榊､ｧ蝠城｡後′蛻､譏・

- 迴ｾ迥ｶ templates/settings.json 縺ｯ Bedrock 蟆ら畑繧ｭ繝ｼ繧偵ワ繝ｼ繝峨さ繝ｼ繝・(CLAUDE_CODE_USE_BEDROCK=1, AWS_REGION, ENABLE_PROMPT_CACHING_1H_BEDROCK=1, AWS_MAX_ATTEMPTS=2, Bedrock 蠖｢蠑・model ID)
- Anthropic API 逶ｴ迺ｰ蠅・↓ apply 縺吶ｋ縺ｨ縲，laude Code 縺梧ｬ｡蝗櫁ｵｷ蜍墓凾縺ｫ Bedrock 謗･邯壹ｒ隧ｦ縺ｿ縲、WS credentials 縺檎┌縺・◆繧・Could not load credentials from any providers 繧ｨ繝ｩ繝ｼ縺ｧ襍ｷ蜍穂ｸ崎・
- user 縺ｮ譌｢蟄・settings.json (萓・ theme, autoUpdatesChannel) 繧ゆｸ頑嶌縺阪〒遐ｴ螢翫＆繧後ｋ

蜉縺医※莉･荳九・譛ｬ雉ｪ逧・撫鬘・

- Bedrock 謗･邯夊ｨｭ螳壹ｄ謗ｨ螂ｨ model ID 縺ｯ蜍慕噪: AWS region縲…ache 莉墓ｧ倥∵眠 model release 縺ｧ螟峨ｏ繧・
- settings.json 縺ｯ user environment config 縺ｮ鬆伜沺: 蛟倶ｺｺ preference (theme) 繧・ｩ溷ｯ・(API key) 繧貞性繧
- 縺薙ｌ縺ｯ CLAUDE.md / rules / agents / skills / commands (kit 縺・ship 縺吶ｋ Claude Code 驛ｨ蜩・ 縺ｨ縺ｯ雋ｬ蜍吶・雉ｪ縺碁＆縺・

## Decision

kit 縺ｯ ~/.claude/settings.json 繧堤函謌舌・荳頑嶌縺阪＠縺ｪ縺・(hands-off)

### 1. templates/settings.json 繧貞炎髯､

apply 譎ゅ・ settings.json 驟榊ｸ・Ο繧ｸ繝・け繧貞ｮ悟・縺ｫ髯､蜴ｻ縲・

### 2. 莉｣繧上ｊ縺ｫ docs/setup/ 縺ｫ險ｭ螳壻ｾ九ｒ驟咲ｽｮ

- docs/setup/settings-bedrock.example.json: Bedrock 迺ｰ蠅・髄縺題ｨｭ螳壻ｾ・(Sonnet 4.5 + Haiku + 1h cache)
- docs/setup/settings-anthropic.example.json: Anthropic API 逶ｴ蜷代￠險ｭ螳壻ｾ・(Sonnet 4.5 + Haiku)
- docs/setup/settings-setup.md: 驕ｸ縺ｳ譁ｹ繧ｬ繧､繝・+ 驕ｩ逕ｨ謇矩・

user 縺梧焔蜍輔〒隧ｲ蠖・example 繧・~/.claude/settings.json 縺ｫ繧ｳ繝斐・ + 蠢・ｦ√↓蠢懊§縺ｦ邱ｨ髮・☆繧九・

### 3. apply-claude-kit.ps1 縺ｧ hint 繝｡繝・そ繝ｼ繧ｸ

apply 螳御ｺ・凾縺ｫ "settings.json 縺ｯ user 閾ｪ霄ｫ縺瑚ｨｭ螳壹＠縺ｦ縺上□縺輔＞縲りｨｭ螳壻ｾ九・ docs/setup/ 繧貞盾辣ｧ" 縺ｨ陦ｨ遉ｺ縲よ里蟄・settings.json 縺後≠繧九°縺ｩ縺・°縺ｫ髢｢繧上ｉ縺壹「ser 縺ｫ菫・☆縺縺代〒隗ｦ繧峨↑縺・・

### 4. config/models.yaml 縺ｮ蠖ｹ蜑ｲ

- model ID 縺ｯ險ｭ螳壻ｾ九・荳ｭ縺ｧ蜿ら・縺輔ｌ繧句ｮ壽焚縺ｨ縺励※菫晄戟
- apply.ps1 縺九ｉ settings.json 縺ｸ縺ｮ蜿ら・縺ｯ蜑企勁
- 蟆・擂 cost-observe-bedrock.ps1 遲峨〒蜿ら・縺吶ｋ蝣ｴ蜷医↓谿九☆

### 5. README / docs / Appendix A 縺ｮ譖ｴ譁ｰ

- ﾂｧ2.1 settings.json 陦後ｒ蜑企勁
- ﾂｧ5 model strategy 縺ｫ kit 縺ｯ settings.json 繧呈署萓帙＠縺ｪ縺・ｒ譏手ｨ・
- bootstrap-installation.md Appendix A 縺ｮ謇矩・°繧・settings.json 閾ｪ蜍暮・蟶・ｒ蜑企勁縲∵焔蜍輔そ繝・ヨ繧｢繝・・繧定ｿｽ蜉

## Alternatives

| 譯・| 謗｡逕ｨ縺励↑縺九▲縺溽炊逕ｱ |
|---|---|
| 讀懷・ + 蜍慕噪逕滓・ (譌ｧ ADR-0007 譯・ | 讀懷・繝ｭ繧ｸ繝・け縺ｫ遨ｴ縲［erge 繝舌げ縲∵里蟄倩ｨｭ螳夂ｴ螢翫∽ｿ｡鬆ｼ繝ｪ繧ｹ繧ｯ縲ょｮ滓ｩ滓､懆ｨｼ縺ｧ螳溷ｮｳ逋ｺ逕・|
| Multiple template files | 邨仙ｱ驕ｸ謚・logic 縺悟ｿ・ｦ√〔it 鬆伜沺螟悶・雋ｬ蜍・|
| User prompt during apply (interactive) | apply 縺ｯ髱槫ｯｾ隧ｱ蜑肴署 (CI 莠呈鋤)縲∝ｯｾ隧ｱ豺ｷ蜈･ NG |
| Hybrid (model ID 縺ｮ縺ｿ譖ｸ縺・ | model ID 蠖｢蠑上′ backend 縺ｧ驕輔≧縺ｮ縺ｧ讀懷・縺ｯ蠢・ｦ√∽ｸｭ騾泌濠遶ｯ |
| Skip-on-existing | 蛻晏屓 install 縺ｧ Bedrock 蠑ｷ蛻ｶ縺ｫ縺ｪ繧贋ｸ榊・蟷ｳ |
| 遨ｺ {} fallback | 闕偵＞ workaround |

## Open questions

- 險ｭ螳壻ｾ九・ format: 荳｡ backend 縺ｧ 1h cache (Bedrock 逕ｨ) 繧貞ｼｷ隱ｿ縺励※譖ｸ縺上°縲∵怙蟆城剞縺ｫ逡吶ａ繧九°
- scripts/validate-settings.ps1 縺ｮ繧医≧縺ｪ讀懆ｨｼ helper 繧呈署萓帙☆繧九° (model ID 縺ｨ CLAUDE_CODE_USE_BEDROCK 縺ｮ謨ｴ蜷医メ繧ｧ繝・け遲・
- bootstrap.ps1 縺ｧ apply 蠕後↓縲瑚ｨｭ螳壻ｾ九ｒ隕九ｋ?縲阪→閨槭￥ UI 繧貞・繧後ｋ縺・(蝓ｺ譛ｬ逧・↓蟇ｾ隧ｱ謗帝勁譁ｹ驥昴↑縺ｮ縺ｧ蜈･繧後↑縺・婿驥昴°)
- docs/setup/ 繧・templates/ 驟堺ｸ九↓遘ｻ縺励※ apply 縺ｧ蜿り・・鄂ｮ縺吶ｋ縺・(user 縺檎峩謗･繧ｳ繝斐・縺励ｄ縺吶＞)

## Implementation plan

(Accepted 譏・ｼ蠕後・蛻･ PR 縺ｧ螳滓命)

1. templates/settings.json 繧貞炎髯､
2. scripts/apply-claude-kit.ps1 縺九ｉ settings.json 驟榊ｸ・Ο繧ｸ繝・け蜑企勁 + hint 繝｡繝・そ繝ｼ繧ｸ霑ｽ蜉
3. docs/setup/settings-bedrock.example.json 譁ｰ隕・(Bedrock 逕ｨ險ｭ螳・
4. docs/setup/settings-anthropic.example.json 譁ｰ隕・(Anthropic 逕ｨ險ｭ螳・
5. docs/setup/settings-setup.md 譁ｰ隕・(驕ｸ縺ｳ譁ｹ + 謇矩・+ 豕ｨ諢冗せ)
6. tests/apply-claude-kit.tests.ps1 縺九ｉ settings.json 髢｢騾｣ test 繧貞炎髯､縲”int 繝｡繝・そ繝ｼ繧ｸ縺ｮ test 繧定ｿｽ蜉
7. README ﾂｧ2.1 (settings.json 陦悟炎髯､) / ﾂｧ5 (hands-off 繝昴Μ繧ｷ繝ｼ譏手ｨ・ / ﾂｧ4 (ADR-0007 霑ｽ蜉)
8. docs/manual-verification/bootstrap-installation.md Appendix A 譖ｴ譁ｰ
9. ADR-0007 繧・Proposed 竊・Accepted縲〉ename 0007-hands-off-settings.md

## Refs

- 逶ｴ謗･縺ｮ蜍墓ｩ・ 2026-06-07 螳滓ｩ滓､懆ｨｼ縺ｧ Could not load credentials from any providers 繧ｨ繝ｩ繝ｼ
- ADR-0001 (kit clean-start design): settings.json 繧呈怙蟆乗ｧ区・縺ｨ縺励※菴懊▲縺溽ｵ檎ｷｯ縲∝・隧穂ｾ｡
- ADR-0004 (auto model routing): model 驕ｸ謚槭・ kit 鬆伜沺縺縺後‘nv 縺ｸ縺ｮ譖ｸ霎ｼ縺ｯ user 鬆伜沺
- 譽・唆縺励◆譌ｧ ADR-0007 譯・(讀懷・ + 蜍慕噪逕滓・): 險ｭ險亥愛譁ｭ縺ｮ邨檎ｷｯ險倬鹸