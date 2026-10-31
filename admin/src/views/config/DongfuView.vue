<template>
  <div>
    <PageHeader title="洞府" desc="药园地块、种子、炼丹配方、试炼/灵气/万年配表，以及灵仆分配系数和设施升级。保存后立刻对玩家生效（开发阶段无草稿）。强化规则仍在「装备强化」页。本页只铺字段，试炼/催熟/灌灵 API 另 PR。">
      <template #actions><el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button></template>
    </PageHeader>

    <DataState :loading="loading && !loaded" :error="error" :has-data="loaded" empty-text="" @retry="load">
      <div class="savebar" :class="{ dirty }">
        <span v-if="!hasSaved" class="state">还没有保存过洞府配置：游戏端药园/炼丹会报错，请先填写并保存（保存后立即生效）。</span>
        <span v-else-if="dirty" class="state">有未保存的改动。</span>
        <span v-else class="state ok">已保存，已对玩家生效。</span>
        <span class="spacer" />
        <el-button @click="fillStarting">填入建议起始值</el-button>
        <el-button :disabled="!dirty" @click="revert">还原</el-button>
        <el-button type="primary" :disabled="!dirty || problems.length > 0" :loading="saving" @click="save">保存</el-button>
      </div>

      <el-alert v-if="problems.length > 0 && touched" type="warning" :closable="false" show-icon class="gap" title="有几项还没填对">
        <ul class="problems"><li v-for="item in problems" :key="item">{{ item }}</li></ul>
      </el-alert>

      <section class="xx-card">
        <h2>通用</h2>
        <el-form label-position="top" class="form grid2">
          <el-form-item label="药园地块数">
            <el-input-number v-model="form.plotCount" :min="1" :max="20" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">玩家同时能种几块地。建议 4。</p>
          </el-form-item>
          <el-form-item label="炼丹队列长度">
            <el-input-number v-model="form.alchemyQueueLength" :min="1" :max="10" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">1 级时同时炼几炉。建议 2。升级在此基础上加队列。</p>
          </el-form-item>
          <el-form-item label="药园地块上限">
            <el-input-number v-model="form.maxPlotCount" :min="1" :max="20" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">升级加地块后不超过这个数。建议 12。</p>
          </el-form-item>
          <el-form-item label="炼丹队列上限">
            <el-input-number v-model="form.maxAlchemyQueue" :min="1" :max="10" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">建议 4。</p>
          </el-form-item>
        </el-form>
      </section>

      <section class="xx-card gap">
        <h2>灵仆与灵木</h2>
        <el-form label-position="top" class="form grid2">
          <el-form-item label="灵木物品">
            <el-select v-model="form.woodItemSlug" filterable allow-create default-first-option placeholder="wood_lingmu" class="full" @change="touched = true">
              <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
            </el-select>
            <p class="hint">升级消耗的材料。须是可堆叠材料，建议先在「物品」页建好。</p>
          </el-form-item>
          <el-form-item label="初始灵木">
            <el-input-number v-model="form.startingWood" :min="0" :max="9999" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">玩家第一次打开洞府时发一次。建议 32。</p>
          </el-form-item>
          <el-form-item label="初始灵仆">
            <el-input-number v-model="form.startingServants" :min="0" :max="99" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">可分到药园或炼丹。闲置没有加成。建议 4。</p>
          </el-form-item>
          <el-form-item label="药园每仆缩短（%）">
            <el-input-number v-model="form.gardenReducePercent" :min="0" :max="100" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">缩短成熟时间，不加产量。建议 5。</p>
          </el-form-item>
          <el-form-item label="炼丹每仆缩短（%）">
            <el-input-number v-model="form.alchemyReducePercent" :min="0" :max="100" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">缩短炼制时间。建议 5。</p>
          </el-form-item>
          <el-form-item label="最短时长（%）">
            <el-input-number v-model="form.minDurationPercent" :min="1" :max="100" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">再多灵仆也不会短于原时长的这个比例。建议 20。</p>
          </el-form-item>
        </el-form>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <div>
            <h2>药园升级</h2>
            <p class="hint">从 2 级连续往上。每一档在地块数上再加「增加数量」。消耗灵木，灵石可填 0。</p>
          </div>
          <el-button type="primary" plain @click="addUpgrade('gardenUpgrades')">加一档</el-button>
        </header>
        <el-table :data="form.gardenUpgrades" size="default">
          <el-table-column label="升到" width="90">
            <template #default="{ row }">{{ row.toLevel }} 级</template>
          </el-table-column>
          <el-table-column label="灵木" width="150">
            <template #default="{ row }">
              <el-input-number v-model="row.wood" :min="0" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="灵石" width="150">
            <template #default="{ row }">
              <el-input-number v-model="row.spiritStones" :min="0" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="增加地块" width="150">
            <template #default="{ row }">
              <el-input-number v-model="row.bonus" :min="1" :max="10" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="" width="70" align="right">
            <template #default="{ $index }">
              <el-button link type="danger" @click="removeUpgrade('gardenUpgrades', $index)">删</el-button>
            </template>
          </el-table-column>
        </el-table>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <div>
            <h2>炼丹升级</h2>
            <p class="hint">每一档给炼丹队列加位。满队列上限后玩家不能再升。</p>
          </div>
          <el-button type="primary" plain @click="addUpgrade('alchemyUpgrades')">加一档</el-button>
        </header>
        <el-table :data="form.alchemyUpgrades" size="default">
          <el-table-column label="升到" width="90">
            <template #default="{ row }">{{ row.toLevel }} 级</template>
          </el-table-column>
          <el-table-column label="灵木" width="150">
            <template #default="{ row }">
              <el-input-number v-model="row.wood" :min="0" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="灵石" width="150">
            <template #default="{ row }">
              <el-input-number v-model="row.spiritStones" :min="0" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="增加队列" width="150">
            <template #default="{ row }">
              <el-input-number v-model="row.bonus" :min="1" :max="10" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="" width="70" align="right">
            <template #default="{ $index }">
              <el-button link type="danger" @click="removeUpgrade('alchemyUpgrades', $index)">删</el-button>
            </template>
          </el-table-column>
        </el-table>
      </section>

      <section class="xx-card gap">
        <h2>摸索丹方（试炼）</h2>
        <el-form label-position="top" class="form grid2">
          <el-form-item label="试炼材料槽数">
            <el-input-number v-model="form.alchemyTrialSlotCount" :min="1" :max="10" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">P1 固定。建议 3。</p>
          </el-form-item>
          <el-form-item label="每日试炼次数">
            <el-input-number v-model="form.alchemyTrialDailyLimit" :min="0" :max="9999" :precision="0" controls-position="right" @change="touched = true" />
          </el-form-item>
          <el-form-item label="超额试炼灵石">
            <el-input-number v-model="form.alchemyTrialExtraCostLingshi" :min="0" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">0 = 禁止超额。</p>
          </el-form-item>
          <el-form-item label="每日超额上限">
            <el-input-number v-model="form.alchemyTrialExtraMax" :min="0" :max="99" :precision="0" controls-position="right" @change="touched = true" />
          </el-form-item>
          <el-form-item label="失败丹道经验">
            <el-input-number v-model="form.alchemyTrialFailXp" :min="0" :max="9999" :precision="0" controls-position="right" @change="touched = true" />
          </el-form-item>
          <el-form-item label="残次丹道经验">
            <el-input-number v-model="form.alchemyTrialImperfectXp" :min="0" :max="9999" :precision="0" controls-position="right" @change="touched = true" />
          </el-form-item>
          <el-form-item label="完美丹道经验">
            <el-input-number v-model="form.alchemyTrialPerfectXp" :min="0" :max="9999" :precision="0" controls-position="right" @change="touched = true" />
          </el-form-item>
          <el-form-item label="提示文案 keys（逗号分隔）">
            <el-input v-model="hintKeysText" placeholder="clash,missing_main,ratio_off,near" @input="touched = true" />
            <p class="hint">服务端只按匹配档位抽 key，不泄题。</p>
          </el-form-item>
        </el-form>
      </section>

      <section class="xx-card gap">
        <h2>药园灵气 / 催熟 / 万年</h2>
        <el-form label-position="top" class="form grid2">
          <el-form-item label="地块灵气上限">
            <el-input-number v-model="form.gardenAuraMax" :min="0" :max="99" :precision="0" controls-position="right" @change="touched = true" />
          </el-form-item>
          <el-form-item label="每点灵气成熟加速（万分比）">
            <el-input-number v-model="form.gardenAuraMatureBpPerPoint" :min="0" :max="10000" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">剩余时间 ×(10000−bp)/10000。建议 500。</p>
          </el-form-item>
          <el-form-item label="每点灵气产量（万分比）">
            <el-input-number v-model="form.gardenAuraYieldBpPerPoint" :min="0" :max="10000" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">P1 建议 0（先只加速）。</p>
          </el-form-item>
          <el-form-item label="催熟每小时灵石">
            <el-input-number v-model="form.gardenHastenLingshiPerHourLeft" :min="0" :precision="0" controls-position="right" @change="touched = true" />
          </el-form-item>
          <el-form-item label="催熟灵露物品（可选）">
            <el-select v-model="form.gardenHastenItemSlug" filterable allow-create clearable default-first-option placeholder="无则只扣灵石" class="full" @change="touched = true">
              <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
            </el-select>
          </el-form-item>
          <el-form-item label="陈年到万年（秒）">
            <el-input-number v-model="form.gardenAgeToAncientSeconds" :min="1" :max="31536000" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">ready→ancient 全局默认；种子行可覆盖。建议 86400。</p>
          </el-form-item>
        </el-form>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <div>
            <h2>灵气来源</h2>
            <p class="hint">P1 先做消耗品一行即可。kind=consumable_item 须填物品。</p>
          </div>
          <el-button type="primary" plain @click="addAuraSource">加一行</el-button>
        </header>
        <el-table :data="form.auraSources" size="default">
          <el-table-column label="编号" min-width="140">
            <template #default="{ row }">
              <el-input v-model="row.sourceSlug" placeholder="item_lingqi_dew" @input="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="类型" width="150">
            <template #default="{ row }">
              <el-select v-model="row.kind" @change="touched = true">
                <el-option label="消耗品" value="consumable_item" />
                <el-option label="设施等级" value="facility_level" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="物品" min-width="160">
            <template #default="{ row }">
              <el-select v-model="row.itemSlug" filterable allow-create clearable default-first-option placeholder="可选" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="灵气+" width="110">
            <template #default="{ row }">
              <el-input-number v-model="row.auraAdd" :min="1" :max="100" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="灵石" width="110">
            <template #default="{ row }">
              <el-input-number v-model="row.lingshiCost" :min="0" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="" width="70" align="right">
            <template #default="{ $index }">
              <el-button link type="danger" @click="removeAuraSource($index)">删</el-button>
            </template>
          </el-table-column>
        </el-table>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <div>
            <h2>种子表</h2>
            <p class="hint">种子物品 → 成熟后产出的草药物品 → 成熟秒数。万年草药选填；缺省则不可进入 ancient。种子/草药须先在「物品」页建好。</p>
          </div>
          <el-button type="primary" plain @click="addSeed">加一种子</el-button>
        </header>
        <el-table :data="form.seeds" size="default">
          <el-table-column label="种子物品" min-width="180">
            <template #default="{ row }">
              <el-select v-model="row.seedSlug" filterable allow-create default-first-option placeholder="选或填编号" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="产出草药" min-width="180">
            <template #default="{ row }">
              <el-select v-model="row.herbSlug" filterable allow-create default-first-option placeholder="选或填编号" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="成熟秒数" width="120">
            <template #default="{ row }">
              <el-input-number v-model="row.growSeconds" :min="1" :max="604800" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="万年草药" min-width="160">
            <template #default="{ row }">
              <el-select v-model="row.ancientHerbSlug" filterable allow-create clearable default-first-option placeholder="可选" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="万年数量" width="110">
            <template #default="{ row }">
              <el-input-number v-model="row.ancientQty" :min="1" :max="9999" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="陈年秒数" width="120">
            <template #default="{ row }">
              <el-input-number v-model="row.ageToAncientSeconds" :min="1" :max="31536000" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="种植灵气" width="100">
            <template #default="{ row }">
              <el-input-number v-model="row.auraGainOnPlant" :min="-100" :max="100" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="" width="70" align="right">
            <template #default="{ $index }">
              <el-button link type="danger" :disabled="form.seeds.length <= 1" @click="removeSeed($index)">删</el-button>
            </template>
          </el-table-column>
        </el-table>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <div>
            <h2>炼丹配方</h2>
            <p class="hint">材料从背包扣；灵石可选。效果保存时会同步到产出物品的 effect（玩家使用丹药读物品效果）。临时属性只能填 attack / defense。</p>
          </div>
          <el-button type="primary" plain @click="addRecipe">加一配方</el-button>
        </header>

        <div v-for="(recipe, rIndex) in form.recipes" :key="rIndex" class="recipe">
          <div class="recipe-head">
            <strong>配方 {{ rIndex + 1 }}</strong>
            <el-button link type="danger" :disabled="form.recipes.length <= 1" @click="removeRecipe(rIndex)">删除配方</el-button>
          </div>
          <el-form label-position="top" class="form recipe-grid">
            <el-form-item label="配方编号">
              <el-input v-model="recipe.recipeSlug" placeholder="pill_cultivate" @input="touched = true" />
            </el-form-item>
            <el-form-item label="产出物品">
              <el-select v-model="recipe.outputItemSlug" filterable allow-create default-first-option placeholder="选或填编号" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </el-form-item>
            <el-form-item label="产出数量">
              <el-input-number v-model="recipe.outputQty" :min="1" :max="9999" :precision="0" controls-position="right" @change="touched = true" />
            </el-form-item>
            <el-form-item label="炼制秒数">
              <el-input-number v-model="recipe.craftSeconds" :min="1" :max="604800" :precision="0" controls-position="right" @change="touched = true" />
            </el-form-item>
            <el-form-item label="灵石消耗（可选）">
              <el-input-number v-model="recipe.spiritStones" :min="0" :precision="0" controls-position="right" @change="touched = true" />
            </el-form-item>
            <el-form-item label="发现模式">
              <el-select v-model="recipe.discoverMode" @change="touched = true">
                <el-option label="教学方 starter" value="starter" />
                <el-option label="隐藏方 hidden" value="hidden" />
              </el-select>
            </el-form-item>
            <el-form-item label="图鉴分组 usageTag">
              <el-input v-model="recipe.usageTag" placeholder="cultivate / atk / def" @input="touched = true" />
            </el-form-item>
            <el-form-item label="残次产出（hidden 建议）">
              <el-select v-model="recipe.imperfectOutputItemSlug" filterable allow-create clearable default-first-option placeholder="可选" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </el-form-item>
            <el-form-item label="残次效果万分比">
              <el-input-number v-model="recipe.imperfectEffectBp" :min="1" :max="10000" :precision="0" controls-position="right" @change="touched = true" />
              <p class="hint">无独立残次物时用，默认 4000。</p>
            </el-form-item>
            <el-form-item label="试炼最少槽">
              <el-input-number v-model="recipe.trialMinSlots" :min="1" :max="10" :precision="0" controls-position="right" @change="touched = true" />
            </el-form-item>
            <el-form-item label="试炼最多槽">
              <el-input-number v-model="recipe.trialMaxSlots" :min="1" :max="10" :precision="0" controls-position="right" @change="touched = true" />
            </el-form-item>
          </el-form>

          <div class="sub">
            <div class="sub-head">
              <span>材料</span>
              <el-button link type="primary" @click="addCost(recipe)">加材料</el-button>
            </div>
            <div v-for="(cost, cIndex) in recipe.costs" :key="cIndex" class="cost-row">
              <el-select v-model="cost.itemSlug" filterable allow-create default-first-option placeholder="物品" class="cost-item" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
              <el-input-number v-model="cost.count" :min="1" :max="9999" :precision="0" size="small" controls-position="right" @change="touched = true" />
              <el-button link type="danger" :disabled="recipe.costs.length <= 1" @click="removeCost(recipe, cIndex)">删</el-button>
            </div>
          </div>

          <div class="sub">
            <div class="sub-head">
              <span>效果（可选，与产出物品共用）</span>
              <el-select :model-value="effectMode(recipe)" placeholder="无效果" clearable style="width: 180px" @change="(v: string | null) => setEffectMode(recipe, v)" @clear="setEffectMode(recipe, null)">
                <el-option label="立刻加修为" value="cultivation" />
                <el-option label="临时攻击" value="attack" />
                <el-option label="临时防御" value="defense" />
              </el-select>
            </div>
            <template v-if="recipe.effect?.cultivationGain != null">
              <el-form-item label="修为获得">
                <el-input-number v-model="recipe.effect.cultivationGain" :min="1" :precision="0" controls-position="right" @change="touched = true" />
              </el-form-item>
            </template>
            <template v-else-if="recipe.effect?.buffStat">
              <el-form label-position="top" class="form recipe-grid">
                <el-form-item label="万分比（1000 = +10%）">
                  <el-input-number v-model="recipe.effect.buffBp" :min="1" :max="100000" :precision="0" controls-position="right" @change="touched = true" />
                </el-form-item>
                <el-form-item label="持续秒数">
                  <el-input-number v-model="recipe.effect.durationSeconds" :min="1" :max="86400" :precision="0" controls-position="right" @change="touched = true" />
                </el-form-item>
              </el-form>
            </template>
          </div>
        </div>
      </section>
    </DataState>
  </div>
</template>

<script setup lang="ts">
import { Refresh } from "@element-plus/icons-vue";
import { ElMessage } from "element-plus";
import { computed, onMounted, ref } from "vue";
import { api } from "../../api";
import DataState from "../../components/DataState.vue";
import PageHeader from "../../components/PageHeader.vue";
import { isConflictAbort } from "../../composables/conflict";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { useDirtyGuard } from "../../composables/dirty";
import { refreshDraftStatus } from "../../composables/draftStatus";
import { useRevisions } from "../../composables/revisions";

type Cost = { itemSlug: string; count: number | null };
type Effect = {
  cultivationGain?: number | null;
  buffStat?: string | null;
  buffBp?: number | null;
  durationSeconds?: number | null;
};
type Seed = {
  seedSlug: string;
  herbSlug: string;
  growSeconds: number | null;
  ancientHerbSlug: string;
  ancientQty: number | null;
  ageToAncientSeconds: number | null;
  auraGainOnPlant: number | null;
};
type UpgradeTier = { toLevel: number; wood: number | null; spiritStones: number | null; bonus: number | null };
type AuraSource = {
  sourceSlug: string;
  kind: "consumable_item" | "facility_level";
  itemSlug: string;
  auraAdd: number | null;
  lingshiCost: number | null;
};
type Recipe = {
  recipeSlug: string;
  outputItemSlug: string;
  outputQty: number | null;
  craftSeconds: number | null;
  spiritStones: number | null;
  costs: Cost[];
  effect?: Effect | null;
  discoverMode: "starter" | "hidden";
  imperfectOutputItemSlug: string;
  imperfectEffectBp: number | null;
  trialMinSlots: number | null;
  trialMaxSlots: number | null;
  usageTag: string;
};
type Form = {
  plotCount: number | null;
  alchemyQueueLength: number | null;
  maxPlotCount: number | null;
  maxAlchemyQueue: number | null;
  woodItemSlug: string;
  startingWood: number | null;
  startingServants: number | null;
  gardenReducePercent: number | null;
  alchemyReducePercent: number | null;
  minDurationPercent: number | null;
  gardenUpgrades: UpgradeTier[];
  alchemyUpgrades: UpgradeTier[];
  alchemyTrialSlotCount: number | null;
  alchemyTrialDailyLimit: number | null;
  alchemyTrialExtraCostLingshi: number | null;
  alchemyTrialExtraMax: number | null;
  alchemyTrialFailXp: number | null;
  alchemyTrialImperfectXp: number | null;
  alchemyTrialPerfectXp: number | null;
  alchemyHintKeys: string[];
  gardenAuraMax: number | null;
  gardenAuraMatureBpPerPoint: number | null;
  gardenAuraYieldBpPerPoint: number | null;
  gardenHastenLingshiPerHourLeft: number | null;
  gardenHastenItemSlug: string;
  gardenAgeToAncientSeconds: number | null;
  auraSources: AuraSource[];
  seeds: Seed[];
  recipes: Recipe[];
};
type View = { config: Form | null; starting: Form };
type ItemRow = { id: string; displayName: string };

const SLUG = /^[a-z][a-z0-9_]*$/;

function emptySeed(): Seed {
  return {
    seedSlug: "",
    herbSlug: "",
    growSeconds: 60,
    ancientHerbSlug: "",
    ancientQty: null,
    ageToAncientSeconds: null,
    auraGainOnPlant: 0,
  };
}
function emptyAuraSource(): AuraSource {
  return { sourceSlug: "", kind: "consumable_item", itemSlug: "", auraAdd: 1, lingshiCost: 0 };
}
function emptyRecipe(): Recipe {
  return {
    recipeSlug: "",
    outputItemSlug: "",
    outputQty: 1,
    craftSeconds: 30,
    spiritStones: 0,
    costs: [{ itemSlug: "", count: 1 }],
    effect: null,
    discoverMode: "starter",
    imperfectOutputItemSlug: "",
    imperfectEffectBp: null,
    trialMinSlots: null,
    trialMaxSlots: null,
    usageTag: "",
  };
}
function defaultGardenUpgrades(): UpgradeTier[] {
  return [
    { toLevel: 2, wood: 8, spiritStones: 0, bonus: 1 },
    { toLevel: 3, wood: 16, spiritStones: 0, bonus: 1 },
    { toLevel: 4, wood: 32, spiritStones: 20, bonus: 1 },
  ];
}
function defaultAlchemyUpgrades(): UpgradeTier[] {
  return [
    { toLevel: 2, wood: 8, spiritStones: 0, bonus: 1 },
    { toLevel: 3, wood: 16, spiritStones: 0, bonus: 1 },
  ];
}
function mapUpgrades(rows: UpgradeTier[] | undefined, fallback: UpgradeTier[]): UpgradeTier[] {
  const source = Array.isArray(rows) ? rows : fallback;
  return source.map((row, index) => ({
    toLevel: index + 2,
    wood: row?.wood ?? 0,
    spiritStones: row?.spiritStones ?? 0,
    bonus: row?.bonus ?? 1,
  }));
}
function emptyForm(): Form {
  return {
    plotCount: 4,
    alchemyQueueLength: 2,
    maxPlotCount: 12,
    maxAlchemyQueue: 4,
    woodItemSlug: "wood_lingmu",
    startingWood: 32,
    startingServants: 4,
    gardenReducePercent: 5,
    alchemyReducePercent: 5,
    minDurationPercent: 20,
    gardenUpgrades: defaultGardenUpgrades(),
    alchemyUpgrades: defaultAlchemyUpgrades(),
    alchemyTrialSlotCount: 3,
    alchemyTrialDailyLimit: 20,
    alchemyTrialExtraCostLingshi: 50,
    alchemyTrialExtraMax: 2,
    alchemyTrialFailXp: 1,
    alchemyTrialImperfectXp: 3,
    alchemyTrialPerfectXp: 10,
    alchemyHintKeys: ["clash", "missing_main", "ratio_off", "near"],
    gardenAuraMax: 5,
    gardenAuraMatureBpPerPoint: 500,
    gardenAuraYieldBpPerPoint: 0,
    gardenHastenLingshiPerHourLeft: 20,
    gardenHastenItemSlug: "",
    gardenAgeToAncientSeconds: 86400,
    auraSources: [],
    seeds: [emptySeed()],
    recipes: [emptyRecipe()],
  };
}

function normalize(raw: Partial<Form> | null | undefined): Form {
  if (!raw) return emptyForm();
  return {
    plotCount: raw.plotCount ?? null,
    alchemyQueueLength: raw.alchemyQueueLength ?? null,
    maxPlotCount: raw.maxPlotCount ?? 12,
    maxAlchemyQueue: raw.maxAlchemyQueue ?? 4,
    woodItemSlug: raw.woodItemSlug || "wood_lingmu",
    startingWood: raw.startingWood ?? 32,
    startingServants: raw.startingServants ?? 4,
    gardenReducePercent: raw.gardenReducePercent ?? 5,
    alchemyReducePercent: raw.alchemyReducePercent ?? 5,
    minDurationPercent: raw.minDurationPercent ?? 20,
    gardenUpgrades: mapUpgrades(raw.gardenUpgrades, defaultGardenUpgrades()),
    alchemyUpgrades: mapUpgrades(raw.alchemyUpgrades, defaultAlchemyUpgrades()),
    alchemyTrialSlotCount: raw.alchemyTrialSlotCount ?? 3,
    alchemyTrialDailyLimit: raw.alchemyTrialDailyLimit ?? 20,
    alchemyTrialExtraCostLingshi: raw.alchemyTrialExtraCostLingshi ?? 50,
    alchemyTrialExtraMax: raw.alchemyTrialExtraMax ?? 2,
    alchemyTrialFailXp: raw.alchemyTrialFailXp ?? 1,
    alchemyTrialImperfectXp: raw.alchemyTrialImperfectXp ?? 3,
    alchemyTrialPerfectXp: raw.alchemyTrialPerfectXp ?? 10,
    alchemyHintKeys: Array.isArray(raw.alchemyHintKeys) && raw.alchemyHintKeys.length
      ? raw.alchemyHintKeys.map(String)
      : ["clash", "missing_main", "ratio_off", "near"],
    gardenAuraMax: raw.gardenAuraMax ?? 5,
    gardenAuraMatureBpPerPoint: raw.gardenAuraMatureBpPerPoint ?? 500,
    gardenAuraYieldBpPerPoint: raw.gardenAuraYieldBpPerPoint ?? 0,
    gardenHastenLingshiPerHourLeft: raw.gardenHastenLingshiPerHourLeft ?? 20,
    gardenHastenItemSlug: raw.gardenHastenItemSlug || "",
    gardenAgeToAncientSeconds: raw.gardenAgeToAncientSeconds ?? 86400,
    auraSources: (raw.auraSources ?? []).map((row) => ({
      sourceSlug: row.sourceSlug ?? "",
      kind: row.kind === "facility_level" ? "facility_level" : "consumable_item",
      itemSlug: row.itemSlug ?? "",
      auraAdd: row.auraAdd ?? 1,
      lingshiCost: row.lingshiCost ?? 0,
    })),
    seeds: (raw.seeds?.length ? raw.seeds : [emptySeed()]).map((row) => ({
      seedSlug: row.seedSlug ?? "",
      herbSlug: row.herbSlug ?? "",
      growSeconds: row.growSeconds ?? null,
      ancientHerbSlug: row.ancientHerbSlug ?? "",
      ancientQty: row.ancientQty ?? null,
      ageToAncientSeconds: row.ageToAncientSeconds ?? null,
      auraGainOnPlant: row.auraGainOnPlant ?? 0,
    })),
    recipes: (raw.recipes?.length ? raw.recipes : [emptyRecipe()]).map((row) => ({
      recipeSlug: row.recipeSlug ?? "",
      outputItemSlug: row.outputItemSlug ?? "",
      outputQty: row.outputQty ?? null,
      craftSeconds: row.craftSeconds ?? null,
      spiritStones: row.spiritStones ?? 0,
      costs: (row.costs?.length ? row.costs : [{ itemSlug: "", count: 1 }]).map((cost) => ({
        itemSlug: cost.itemSlug ?? "",
        count: cost.count ?? null,
      })),
      effect: row.effect
        ? {
            cultivationGain: row.effect.cultivationGain ?? null,
            buffStat: row.effect.buffStat ?? null,
            buffBp: row.effect.buffBp ?? null,
            durationSeconds: row.effect.durationSeconds ?? null,
          }
        : null,
      discoverMode: row.discoverMode === "hidden" ? "hidden" : "starter",
      imperfectOutputItemSlug: row.imperfectOutputItemSlug ?? "",
      imperfectEffectBp: row.imperfectEffectBp ?? null,
      trialMinSlots: row.trialMinSlots ?? null,
      trialMaxSlots: row.trialMaxSlots ?? null,
      usageTag: row.usageTag ?? "",
    })),
  };
}

function payload(form: Form): Record<string, unknown> {
  return {
    plotCount: form.plotCount,
    alchemyQueueLength: form.alchemyQueueLength,
    maxPlotCount: form.maxPlotCount,
    maxAlchemyQueue: form.maxAlchemyQueue,
    woodItemSlug: form.woodItemSlug.trim(),
    startingWood: form.startingWood,
    startingServants: form.startingServants,
    gardenReducePercent: form.gardenReducePercent,
    alchemyReducePercent: form.alchemyReducePercent,
    minDurationPercent: form.minDurationPercent,
    gardenUpgrades: form.gardenUpgrades.map((row, index) => ({
      toLevel: index + 2,
      wood: row.wood ?? 0,
      spiritStones: row.spiritStones ?? 0,
      bonus: row.bonus ?? 1,
    })),
    alchemyUpgrades: form.alchemyUpgrades.map((row, index) => ({
      toLevel: index + 2,
      wood: row.wood ?? 0,
      spiritStones: row.spiritStones ?? 0,
      bonus: row.bonus ?? 1,
    })),
    alchemyTrialSlotCount: form.alchemyTrialSlotCount,
    alchemyTrialDailyLimit: form.alchemyTrialDailyLimit,
    alchemyTrialExtraCostLingshi: form.alchemyTrialExtraCostLingshi,
    alchemyTrialExtraMax: form.alchemyTrialExtraMax,
    alchemyTrialFailXp: form.alchemyTrialFailXp,
    alchemyTrialImperfectXp: form.alchemyTrialImperfectXp,
    alchemyTrialPerfectXp: form.alchemyTrialPerfectXp,
    alchemyHintKeys: form.alchemyHintKeys,
    gardenAuraMax: form.gardenAuraMax,
    gardenAuraMatureBpPerPoint: form.gardenAuraMatureBpPerPoint,
    gardenAuraYieldBpPerPoint: form.gardenAuraYieldBpPerPoint,
    gardenHastenLingshiPerHourLeft: form.gardenHastenLingshiPerHourLeft,
    gardenHastenItemSlug: form.gardenHastenItemSlug.trim() || null,
    gardenAgeToAncientSeconds: form.gardenAgeToAncientSeconds,
    auraSources: form.auraSources.map((row) => {
      const out: Record<string, unknown> = {
        sourceSlug: row.sourceSlug.trim(),
        kind: row.kind,
        auraAdd: row.auraAdd,
      };
      if (row.itemSlug.trim()) out.itemSlug = row.itemSlug.trim();
      if (row.lingshiCost != null) out.lingshiCost = row.lingshiCost;
      return out;
    }),
    seeds: form.seeds.map((row) => {
      const out: Record<string, unknown> = {
        seedSlug: row.seedSlug.trim(),
        herbSlug: row.herbSlug.trim(),
        growSeconds: row.growSeconds,
      };
      if (row.ancientHerbSlug.trim()) out.ancientHerbSlug = row.ancientHerbSlug.trim();
      if (row.ancientQty != null) out.ancientQty = row.ancientQty;
      if (row.ageToAncientSeconds != null) out.ageToAncientSeconds = row.ageToAncientSeconds;
      if (row.auraGainOnPlant != null && row.auraGainOnPlant !== 0) out.auraGainOnPlant = row.auraGainOnPlant;
      return out;
    }),
    recipes: form.recipes.map((row) => {
      const out: Record<string, unknown> = {
        recipeSlug: row.recipeSlug.trim(),
        outputItemSlug: row.outputItemSlug.trim(),
        outputQty: row.outputQty,
        craftSeconds: row.craftSeconds,
        spiritStones: row.spiritStones ?? 0,
        discoverMode: row.discoverMode || "starter",
        costs: row.costs.map((cost) => ({ itemSlug: cost.itemSlug.trim(), count: cost.count })),
      };
      if (row.usageTag.trim()) out.usageTag = row.usageTag.trim();
      if (row.imperfectOutputItemSlug.trim()) out.imperfectOutputItemSlug = row.imperfectOutputItemSlug.trim();
      if (row.imperfectEffectBp != null) out.imperfectEffectBp = row.imperfectEffectBp;
      if (row.trialMinSlots != null) out.trialMinSlots = row.trialMinSlots;
      if (row.trialMaxSlots != null) out.trialMaxSlots = row.trialMaxSlots;
      if (row.effect?.cultivationGain != null) {
        out.effect = { cultivationGain: row.effect.cultivationGain };
      } else if (row.effect?.buffStat) {
        out.effect = {
          buffStat: row.effect.buffStat,
          buffBp: row.effect.buffBp,
          durationSeconds: row.effect.durationSeconds,
        };
      }
      return out;
    }),
  };
}

function clientProblems(form: Form): string[] {
  const list: string[] = [];
  if (form.plotCount == null || form.plotCount < 1 || form.plotCount > 20) list.push("地块数要在 1～20");
  if (form.alchemyQueueLength == null || form.alchemyQueueLength < 1 || form.alchemyQueueLength > 10) list.push("炼丹队列要在 1～10");
  if (form.maxPlotCount == null || form.maxPlotCount < 1 || form.maxPlotCount > 20) list.push("药园地块上限要在 1～20");
  else if (form.plotCount != null && form.maxPlotCount < form.plotCount) list.push("药园地块上限不能小于地块数");
  if (form.maxAlchemyQueue == null || form.maxAlchemyQueue < 1 || form.maxAlchemyQueue > 10) list.push("炼丹队列上限要在 1～10");
  else if (form.alchemyQueueLength != null && form.maxAlchemyQueue < form.alchemyQueueLength) list.push("炼丹队列上限不能小于队列长度");
  if (!SLUG.test(form.woodItemSlug)) list.push("灵木物品编号格式不对");
  if (form.startingWood == null || form.startingWood < 0) list.push("初始灵木要 ≥ 0");
  if (form.startingServants == null || form.startingServants < 0) list.push("初始灵仆要 ≥ 0");
  if (form.gardenReducePercent == null || form.gardenReducePercent < 0 || form.gardenReducePercent > 100) list.push("药园每仆缩短要在 0～100");
  if (form.alchemyReducePercent == null || form.alchemyReducePercent < 0 || form.alchemyReducePercent > 100) list.push("炼丹每仆缩短要在 0～100");
  if (form.minDurationPercent == null || form.minDurationPercent < 1 || form.minDurationPercent > 100) list.push("最短时长要在 1～100");
  if (form.alchemyTrialSlotCount == null || form.alchemyTrialSlotCount < 1 || form.alchemyTrialSlotCount > 10) list.push("试炼槽数要在 1～10");
  if (form.alchemyTrialDailyLimit == null || form.alchemyTrialDailyLimit < 0) list.push("每日试炼次数要 ≥ 0");
  if (form.alchemyTrialExtraCostLingshi == null || form.alchemyTrialExtraCostLingshi < 0) list.push("超额试炼灵石要 ≥ 0");
  if (form.alchemyTrialExtraMax == null || form.alchemyTrialExtraMax < 0) list.push("每日超额上限要 ≥ 0");
  if (!form.alchemyHintKeys.length) list.push("至少一条提示文案 key");
  form.alchemyHintKeys.forEach((key, index) => {
    if (!SLUG.test(key)) list.push(`提示 key 第 ${index + 1} 项格式不对`);
  });
  if (form.gardenAuraMax == null || form.gardenAuraMax < 0) list.push("地块灵气上限要 ≥ 0");
  if (form.gardenAuraMatureBpPerPoint == null || form.gardenAuraMatureBpPerPoint < 0 || form.gardenAuraMatureBpPerPoint > 10000) {
    list.push("灵气成熟加速万分比要在 0～10000");
  }
  if (form.gardenAuraYieldBpPerPoint == null || form.gardenAuraYieldBpPerPoint < 0 || form.gardenAuraYieldBpPerPoint > 10000) {
    list.push("灵气产量万分比要在 0～10000");
  }
  if (form.gardenHastenLingshiPerHourLeft == null || form.gardenHastenLingshiPerHourLeft < 0) list.push("催熟每小时灵石要 ≥ 0");
  if (form.gardenHastenItemSlug && !SLUG.test(form.gardenHastenItemSlug)) list.push("催熟灵露物品编号格式不对");
  if (form.gardenAgeToAncientSeconds == null || form.gardenAgeToAncientSeconds < 1) list.push("陈年到万年秒数要 ≥ 1");
  const auraSeen = new Set<string>();
  form.auraSources.forEach((row, index) => {
    const label = `灵气来源第 ${index + 1} 行`;
    if (!SLUG.test(row.sourceSlug)) list.push(`${label}：编号格式不对`);
    else if (auraSeen.has(row.sourceSlug)) list.push(`灵气来源编号重复：${row.sourceSlug}`);
    else auraSeen.add(row.sourceSlug);
    if (row.kind === "consumable_item" && !SLUG.test(row.itemSlug)) list.push(`${label}：消耗品须填物品`);
    if (row.itemSlug && !SLUG.test(row.itemSlug)) list.push(`${label}：物品编号格式不对`);
    if (row.auraAdd == null || row.auraAdd < 1) list.push(`${label}：灵气增量要 ≥ 1`);
    if (row.lingshiCost != null && row.lingshiCost < 0) list.push(`${label}：灵石要 ≥ 0`);
  });
  const checkTiers = (rows: UpgradeTier[], label: string) => {
    rows.forEach((row, index) => {
      if (row.wood == null || row.wood < 0) list.push(`${label}第 ${index + 1} 档：灵木要 ≥ 0`);
      if (row.spiritStones == null || row.spiritStones < 0) list.push(`${label}第 ${index + 1} 档：灵石要 ≥ 0`);
      if (row.bonus == null || row.bonus < 1) list.push(`${label}第 ${index + 1} 档：增加数量要 ≥ 1`);
    });
  };
  checkTiers(form.gardenUpgrades, "药园升级");
  checkTiers(form.alchemyUpgrades, "炼丹升级");
  if (!form.seeds.length) list.push("至少一种种子");
  const seedSeen = new Set<string>();
  form.seeds.forEach((row, index) => {
    if (!SLUG.test(row.seedSlug)) list.push(`种子第 ${index + 1} 行：种子编号格式不对`);
    else if (seedSeen.has(row.seedSlug)) list.push(`种子编号重复：${row.seedSlug}`);
    else seedSeen.add(row.seedSlug);
    if (!SLUG.test(row.herbSlug)) list.push(`种子第 ${index + 1} 行：草药编号格式不对`);
    if (row.growSeconds == null || row.growSeconds < 1) list.push(`种子第 ${index + 1} 行：成熟秒数要 ≥ 1`);
    if (row.ancientHerbSlug && !SLUG.test(row.ancientHerbSlug)) list.push(`种子第 ${index + 1} 行：万年草药编号格式不对`);
    if (row.ancientHerbSlug && row.ancientQty != null && row.ancientQty < 1) list.push(`种子第 ${index + 1} 行：万年数量要 ≥ 1`);
    if (row.ageToAncientSeconds != null && row.ageToAncientSeconds < 1) list.push(`种子第 ${index + 1} 行：陈年秒数要 ≥ 1`);
  });
  if (!form.recipes.length) list.push("至少一种配方");
  const recipeSeen = new Set<string>();
  form.recipes.forEach((row, index) => {
    const label = `配方第 ${index + 1} 行`;
    if (!SLUG.test(row.recipeSlug)) list.push(`${label}：配方编号格式不对`);
    else if (recipeSeen.has(row.recipeSlug)) list.push(`配方编号重复：${row.recipeSlug}`);
    else recipeSeen.add(row.recipeSlug);
    if (!SLUG.test(row.outputItemSlug)) list.push(`${label}：产出编号格式不对`);
    if (row.outputQty == null || row.outputQty < 1) list.push(`${label}：产出数量要 ≥ 1`);
    if (row.craftSeconds == null || row.craftSeconds < 1) list.push(`${label}：炼制秒数要 ≥ 1`);
    if (row.discoverMode !== "starter" && row.discoverMode !== "hidden") list.push(`${label}：发现模式只能是 starter 或 hidden`);
    if (row.usageTag && !SLUG.test(row.usageTag)) list.push(`${label}：usageTag 格式不对`);
    if (row.imperfectOutputItemSlug && !SLUG.test(row.imperfectOutputItemSlug)) list.push(`${label}：残次产出编号格式不对`);
    if (row.imperfectEffectBp != null && (row.imperfectEffectBp < 1 || row.imperfectEffectBp > 10000)) {
      list.push(`${label}：残次效果万分比要在 1～10000`);
    }
    if (row.trialMinSlots != null && row.trialMaxSlots != null && row.trialMinSlots > row.trialMaxSlots) {
      list.push(`${label}：试炼最少槽不能大于最多槽`);
    }
    if (!row.costs.length) list.push(`${label}：至少一种材料`);
    row.costs.forEach((cost, cIndex) => {
      if (!SLUG.test(cost.itemSlug)) list.push(`${label}材料 ${cIndex + 1}：编号格式不对`);
      if (cost.count == null || cost.count < 1) list.push(`${label}材料 ${cIndex + 1}：数量要 ≥ 1`);
    });
    if (row.effect?.cultivationGain != null && row.effect.cultivationGain < 1) list.push(`${label}：修为获得要 ≥ 1`);
    if (row.effect?.buffStat) {
      if (row.effect.buffBp == null || row.effect.buffBp < 1) list.push(`${label}：临时属性万分比要 ≥ 1`);
      if (row.effect.durationSeconds == null || row.effect.durationSeconds < 1) list.push(`${label}：持续秒数要 ≥ 1`);
    }
  });
  return list;
}

const loading = ref(false);
const saving = ref(false);
const loaded = ref(false);
const error = ref("");
const touched = ref(false);
const hasSaved = ref(false);
const form = ref<Form>(emptyForm());
const original = ref("");
const starting = ref<Form | null>(null);
const items = ref<ItemRow[]>([]);

const dirty = computed(() => original.value !== "" && JSON.stringify(form.value) !== original.value);
const problems = computed(() => clientProblems(form.value));
useDirtyGuard(dirty);

const itemOptions = computed(() =>
  items.value.map((item) => ({ value: item.id, label: `${item.displayName}（${item.id}）` })),
);

function effectMode(recipe: Recipe): string | null {
  if (recipe.effect?.cultivationGain != null) return "cultivation";
  if (recipe.effect?.buffStat === "attack") return "attack";
  if (recipe.effect?.buffStat === "defense") return "defense";
  return null;
}

function setEffectMode(recipe: Recipe, mode: string | null): void {
  touched.value = true;
  if (!mode) {
    recipe.effect = null;
    return;
  }
  if (mode === "cultivation") {
    recipe.effect = { cultivationGain: recipe.effect?.cultivationGain ?? 100 };
    return;
  }
  recipe.effect = {
    buffStat: mode,
    buffBp: recipe.effect?.buffBp ?? 1000,
    durationSeconds: recipe.effect?.durationSeconds ?? 300,
  };
}

function addUpgrade(key: "gardenUpgrades" | "alchemyUpgrades"): void {
  form.value[key].push({ toLevel: form.value[key].length + 2, wood: 8, spiritStones: 0, bonus: 1 });
  touched.value = true;
}
function removeUpgrade(key: "gardenUpgrades" | "alchemyUpgrades", index: number): void {
  form.value[key].splice(index, 1);
  form.value[key].forEach((row, rowIndex) => {
    row.toLevel = rowIndex + 2;
  });
  touched.value = true;
}
const hintKeysText = computed({
  get: () => form.value.alchemyHintKeys.join(","),
  set: (value: string) => {
    form.value.alchemyHintKeys = value
      .split(/[,，\s]+/)
      .map((part) => part.trim())
      .filter(Boolean);
  },
});

function addAuraSource(): void {
  form.value.auraSources.push(emptyAuraSource());
  touched.value = true;
}
function removeAuraSource(index: number): void {
  form.value.auraSources.splice(index, 1);
  touched.value = true;
}
function addSeed(): void {
  form.value.seeds.push(emptySeed());
  touched.value = true;
}
function removeSeed(index: number): void {
  form.value.seeds.splice(index, 1);
  touched.value = true;
}
function addRecipe(): void {
  form.value.recipes.push(emptyRecipe());
  touched.value = true;
}
function removeRecipe(index: number): void {
  form.value.recipes.splice(index, 1);
  touched.value = true;
}
function addCost(recipe: Recipe): void {
  recipe.costs.push({ itemSlug: "", count: 1 });
  touched.value = true;
}
function removeCost(recipe: Recipe, index: number): void {
  recipe.costs.splice(index, 1);
  touched.value = true;
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

const rev = useRevisions("globals");

async function loadItems(): Promise<void> {
  try {
    items.value = await api<ItemRow[]>("/admin/draft/items");
  } catch {
    items.value = [];
  }
}

async function load(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    await rev.load();
    const [view] = await Promise.all([api<View>("/admin/draft/dongfu"), loadItems()]);
    starting.value = normalize(view.starting);
    hasSaved.value = view.config !== null;
    form.value = normalize(view.config ?? view.starting);
    original.value = JSON.stringify(form.value);
    touched.value = false;
    loaded.value = true;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function fillStarting(): void {
  if (!starting.value) return;
  form.value = normalize(clone(starting.value));
  touched.value = true;
  ElMessage.info("已填入建议起始值，还没有保存。");
}

function revert(): void {
  form.value = original.value ? (JSON.parse(original.value) as Form) : emptyForm();
  touched.value = false;
}

async function save(): Promise<void> {
  touched.value = true;
  if (problems.value.length > 0) {
    ElMessage.warning(problems.value[0]);
    return;
  }
  saving.value = true;
  try {
    const view = await api<View>("/admin/draft/dongfu", {
      method: "PUT",
      body: JSON.stringify(payload(form.value)),
      guard: {
        revisions: rev,
        id: 1,
        reload: load,
        latest: async () => (await api<View>("/admin/draft/dongfu")).config,
        title: "洞府配置",
      },
    });
    hasSaved.value = view.config !== null;
    if (view.config) form.value = normalize(view.config);
    original.value = JSON.stringify(form.value);
    touched.value = false;
    ElMessage.success("已保存，已生效");
    void refreshDraftStatus();
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
    } else ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

useRefetchOnActivate(load);
onMounted(load);
</script>

<style scoped>
.savebar {
  position: sticky;
  top: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  margin-bottom: var(--xx-space-4);
  padding: var(--xx-space-2) var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-surface);
  box-shadow: var(--xx-shadow-card);
}
.savebar.dirty {
  border-color: var(--xx-warning);
  background: var(--xx-warning-bg);
}
.state {
  font-size: var(--xx-fs-sm);
}
.state.ok {
  color: var(--xx-text-secondary);
}
.spacer {
  flex: 1;
}
.gap {
  margin-top: var(--xx-space-4);
}
h2 {
  margin: 0 0 var(--xx-space-3);
  font-size: var(--xx-fs-lg);
}
.head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--xx-space-3);
  margin-bottom: var(--xx-space-3);
}
.head h2 {
  margin-bottom: 4px;
}
.hint {
  margin: 4px 0 0;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
  line-height: 1.5;
}
.form :deep(.el-input-number) {
  width: 160px;
}
.grid2 {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 280px));
  gap: var(--xx-space-3);
}
.full {
  width: 100%;
}
.problems {
  margin: 4px 0 0;
  padding-left: 18px;
}
.recipe {
  padding: var(--xx-space-3);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-subtle);
  margin-bottom: var(--xx-space-3);
}
.recipe-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--xx-space-2);
}
.recipe-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: var(--xx-space-2) var(--xx-space-3);
}
.sub {
  margin-top: var(--xx-space-3);
  padding-top: var(--xx-space-2);
  border-top: 1px dashed var(--xx-border);
}
.sub-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--xx-space-2);
  font-size: var(--xx-fs-sm);
  color: var(--xx-text-secondary);
}
.cost-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}
.cost-item {
  flex: 1;
  min-width: 180px;
}
</style>
