<script setup>
import { computed, ref, watch } from "vue";
import { api, errorMessage } from "../api";
import { groupHistory, dateInShanghai, shiftDay, isAdditive } from "../history";

const props = defineProps({
  workspaceId: Number,
  kind: String,
  entities: Array,
  metrics: Array,
});
const selectedId = ref(null);
const metricCode = ref("weight_kg");
const period = ref(30);
const dates = ref([]);
const grouping = ref("day");
const rows = ref([]);
const loading = ref(false);
const root = ref(null);
defineExpose({
  select(id) {
    selectedId.value = id;
    root.value?.scrollIntoView({ behavior: "smooth", block: "start" });
  },
});
const error = ref("");
let requestId = 0;
const today = () => dateInShanghai(new Date());
function preset() {
  dates.value = [shiftDay(today(), 1 - period.value), today()];
}
preset();
watch(
  () => [props.workspaceId, props.entities.map((x) => x.id).join(",")],
  () => {
    if (!props.entities.some((x) => x.id === selectedId.value))
      selectedId.value = props.entities[0]?.id ?? null;
  },
  { immediate: true },
);
async function refresh() {
  const current = ++requestId;
  rows.value = [];
  error.value = "";
  if (!selectedId.value || dates.value?.length !== 2) {
    loading.value = false;
    return;
  }
  const [start, end] = dates.value;
  if (start > end || (Date.parse(end) - Date.parse(start)) / 86400000 > 365) {
    error.value = "请选择有效日期，范围不超过 366 天";
    loading.value = false;
    return;
  }
  loading.value = true;
  try {
    const query = new URLSearchParams({
      [`${props.kind}Id`]: selectedId.value,
      start,
      end,
    });
    const result = await api(
      "get",
      `/workspaces/${props.workspaceId}/measurements/history?${query}`,
    );
    if (current !== requestId) return;
    rows.value = result;
    if (!result.some((x) => x.metricCode === metricCode.value) && result.length)
      metricCode.value = result[0].metricCode;
  } catch (e) {
    if (current === requestId) error.value = errorMessage(e);
  } finally {
    if (current === requestId) loading.value = false;
  }
}
watch(
  () => [props.workspaceId, selectedId.value, ...(dates.value || [])],
  refresh,
  { immediate: true },
);
const entity = computed(() =>
  props.entities.find((x) => x.id === selectedId.value),
);
const metricOptions = computed(() =>
  props.metrics.filter((x) => props.kind === "device" || x.scope === "PET"),
);
const metric = computed(() =>
  props.metrics.find((x) => x.code === metricCode.value),
);
const additive = computed(() => isAdditive(metricCode.value));
const selectedRows = computed(() =>
  rows.value.filter((x) => x.metricCode === metricCode.value),
);
const groups = computed(() => groupHistory(selectedRows.value, grouping.value));
const count = computed(() =>
  selectedRows.value.reduce((n, x) => n + Number(x.count), 0),
);
const sum = computed(() =>
  selectedRows.value.reduce((n, x) => n + Number(x.total), 0),
);
const average = computed(() => (count.value ? sum.value / count.value : null));
const manual = computed(() =>
  selectedRows.value.reduce((n, x) => n + Number(x.manualCount), 0),
);
const manualPercent = computed(() =>
  count.value ? (manual.value / count.value) * 100 : 0,
);
const unit = computed(() => metric.value?.unit || "");
const fmt = (value) =>
  value == null
    ? "—"
    : Number(value).toLocaleString("zh-CN", { maximumFractionDigits: 3 });
const values = computed(() =>
  groups.value.map((x) => (additive.value ? x.total : x.average)),
);
const ceiling = computed(() => Math.max(...values.value, 0) * 1.1 || 1);
const floor = computed(() => Math.min(...values.value, 0));
const lineFloor = computed(() => {
  const low = Math.min(...values.value);
  const high = Math.max(...values.value);
  return low - Math.max((high - low) * 0.15, Math.abs(low) * 0.01, 0.01);
});
const lineCeiling = computed(() => {
  const high = Math.max(...values.value);
  const low = Math.min(...values.value);
  return high + Math.max((high - low) * 0.15, Math.abs(high) * 0.01, 0.01);
});
const lineY = (value) =>
  210 -
  ((value - lineFloor.value) / (lineCeiling.value - lineFloor.value)) * 170;
const y = (value) =>
  210 - ((value - floor.value) / (ceiling.value - floor.value)) * 170;
const x = (i) =>
  groups.value.length === 1 ? 350 : 60 + (i * 580) / (groups.value.length - 1);
const points = computed(() =>
  groups.value.map((g, i) => `${x(i)},${lineY(values.value[i])}`).join(" "),
);
const barWidth = computed(() =>
  Math.min(38, 520 / Math.max(groups.value.length, 1)),
);
const barX = (i) => 60 + ((i + 0.5) * 580) / groups.value.length;
const tickVisible = (i) =>
  i === 0 ||
  i === groups.value.length - 1 ||
  i % Math.max(1, Math.ceil(groups.value.length / 7)) === 0;
const tip = (g, i) =>
  `${g.label}：${fmt(values.value[i])} ${unit.value}；${g.count} 条记录`;
const pagedRows = computed(() =>
  [...groups.value]
    .reverse()
    .slice((tablePage.value - 1) * 10, tablePage.value * 10),
);
const tablePage = ref(1);
watch(groups, () => {
  tablePage.value = 1;
});
</script>

<template>
  <section ref="root" class="panel history-panel" v-loading="loading">
    <div class="panel-head">
      <div>
        <p class="eyebrow">HISTORY & TRENDS</p>
        <h2>{{ kind === "pet" ? "宠物健康趋势" : "设备历史测量" }}</h2>
        <p class="history-muted">
          {{ entity?.name || "请选择对象" }} · 按上海日期统计
        </p>
      </div>
      <el-button @click="refresh" :disabled="!selectedId">刷新数据</el-button>
    </div>
    <div class="history-filters">
      <label
        >查看对象<el-select
          v-model="selectedId"
          :placeholder="kind === 'pet' ? '选择宠物' : '选择设备'"
          ><el-option
            v-for="item in entities"
            :key="item.id"
            :label="item.name"
            :value="item.id" /></el-select
      ></label>
      <label
        >观察指标<el-select v-model="metricCode"
          ><el-option
            v-for="item in metricOptions"
            :key="item.code"
            :label="`${item.label} (${item.unit})`"
            :value="item.code" /></el-select
      ></label>
      <label
        >时间范围<el-select v-model="period" @change="preset"
          ><el-option
            v-for="days in [7, 30, 90]"
            :key="days"
            :label="`近 ${days} 天`"
            :value="days" /></el-select
      ></label>
      <label
        >统计粒度<el-select v-model="grouping"
          ><el-option label="按天" value="day" /><el-option
            label="按周（周一开始）"
            value="week" /></el-select
      ></label>
      <label class="history-date"
        >自选日期<el-date-picker
          v-model="dates"
          type="daterange"
          value-format="YYYY-MM-DD"
          range-separator="至"
          start-placeholder="开始日期"
          end-placeholder="结束日期"
          :clearable="false"
      /></label>
    </div>
    <el-alert
      v-if="error"
      :title="error"
      type="error"
      :closable="false"
      show-icon
    />
    <el-empty
      v-else-if="!count && !loading"
      :description="
        selectedId
          ? '该时段暂无此指标记录，请调整指标或日期范围'
          : '添加宠物或设备后，即可查看历史趋势'
      "
    />
    <template v-else-if="count">
      <div class="history-stats">
        <div>
          <span>记录数量</span><strong>{{ count }} <small>条</small></strong>
        </div>
        <div>
          <span>期间均值</span
          ><strong
            >{{ fmt(average) }} <small>{{ unit }}</small></strong
          >
        </div>
        <div>
          <span>{{ additive ? "期间累计" : "期间最高" }}</span
          ><strong
            >{{
              fmt(
                additive
                  ? sum
                  : Math.max(...selectedRows.map((x) => Number(x.maximum))),
              )
            }}
            <small>{{ unit }}</small></strong
          >
        </div>
        <div>
          <span>期间最低</span
          ><strong
            >{{ fmt(Math.min(...selectedRows.map((x) => Number(x.minimum)))) }}
            <small>{{ unit }}</small></strong
          >
        </div>
      </div>
      <p class="history-muted">
        {{ metric?.label }}：{{
          additive
            ? "折线与柱形均显示各阶段累计值"
            : "折线与柱形均显示各阶段均值"
        }}。无记录日期不补零；折线仅连接有记录的阶段。周统计在所选日期范围内汇总。折线纵轴随数值缩放，柱形以零为基线；窄屏图表可横向滚动。
      </p>
      <div class="history-chart-grid">
        <article class="history-chart">
          <h3>
            {{ metric?.label }}趋势 <small>{{ unit }}</small>
          </h3>
          <svg
            viewBox="0 0 700 260"
            role="img"
            :aria-label="`${metric?.label}历史折线图`"
          >
            <g v-for="i in [0, 1, 2, 3, 4]" :key="i">
              <line
                x1="60"
                x2="660"
                :y1="40 + i * 42.5"
                :y2="40 + i * 42.5"
                class="history-grid"
              />
              <text x="52" :y="44 + i * 42.5" text-anchor="end">
                {{ fmt(lineCeiling - (i * (lineCeiling - lineFloor)) / 4) }}
              </text>
            </g>
            <polyline
              :points="points"
              fill="none"
              stroke="#47876b"
              stroke-width="3"
            />
            <g v-for="(g, i) in groups" :key="g.label">
              <circle
                :cx="x(i)"
                :cy="lineY(values[i])"
                r="4"
                fill="#47876b"
                tabindex="0"
              >
                <title>{{ tip(g, i) }}</title>
              </circle>
              <text
                v-if="tickVisible(i)"
                :x="x(i)"
                y="239"
                text-anchor="middle"
              >
                {{ g.label.slice(5) }}
              </text>
            </g>
          </svg>
        </article>
        <article class="history-chart">
          <h3>
            阶段{{ additive ? "累计" : "均值" }}对比 <small>{{ unit }}</small>
          </h3>
          <svg
            viewBox="0 0 700 260"
            role="img"
            :aria-label="`${metric?.label}阶段柱状图`"
          >
            <g v-for="i in [0, 1, 2, 3, 4]" :key="i">
              <line
                x1="60"
                x2="660"
                :y1="40 + i * 42.5"
                :y2="40 + i * 42.5"
                class="history-grid"
              />
              <text x="52" :y="44 + i * 42.5" text-anchor="end">
                {{ fmt(ceiling - (i * (ceiling - floor)) / 4) }}
              </text>
            </g>
            <g v-for="(g, i) in groups" :key="g.label">
              <rect
                :x="barX(i) - barWidth / 2"
                :y="Math.min(y(0), y(values[i]))"
                :width="barWidth"
                :height="Math.max(1, Math.abs(y(0) - y(values[i])))"
                rx="3"
                fill="#90bba5"
                tabindex="0"
              >
                <title>{{ tip(g, i) }}</title>
              </rect>
              <text
                v-if="tickVisible(i)"
                :x="barX(i)"
                y="239"
                text-anchor="middle"
              >
                {{ g.label.slice(5) }}
              </text>
            </g>
          </svg>
        </article>
      </div>
      <div class="history-bottom-grid">
        <article class="history-chart">
          <h3>记录来源占比</h3>
          <p class="history-muted">当前对象、指标及时段的记录条数</p>
          <div
            class="history-donut"
            role="img"
            :aria-label="`人工记录 ${manual} 条，设备上报 ${count - manual} 条`"
            :style="{
              background: `conic-gradient(#47876b 0% ${manualPercent}%, #bad3e5 ${manualPercent}% 100%)`,
            }"
          >
            <div>
              <strong>{{ count }}</strong
              ><span>条记录</span>
            </div>
          </div>
          <div class="history-legend">
            <span
              ><i style="background: #47876b"></i>人工 {{ manual }} ·
              {{ fmt(manualPercent) }}%</span
            ><span
              ><i style="background: #bad3e5"></i>设备 {{ count - manual }} ·
              {{ fmt(100 - manualPercent) }}%</span
            >
          </div>
        </article>
        <article class="history-chart history-table">
          <h3>
            阶段数据明细 <small>{{ unit }}</small>
          </h3>
          <el-table :data="pagedRows" size="small"
            ><el-table-column
              prop="label"
              :label="grouping === 'day' ? '日期' : '周起始日期'"
              min-width="115"
            /><el-table-column
              prop="count"
              label="条数"
              width="65"
            /><el-table-column label="均值" min-width="85"
              ><template #default="{ row }">{{
                fmt(row.average)
              }}</template></el-table-column
            ><el-table-column label="最低 / 最高" min-width="130"
              ><template #default="{ row }"
                >{{ fmt(row.minimum) }} / {{ fmt(row.maximum) }}</template
              ></el-table-column
            ><el-table-column v-if="additive" label="累计" min-width="85"
              ><template #default="{ row }">{{
                fmt(row.total)
              }}</template></el-table-column
            ></el-table
          ><el-pagination
            v-if="groups.length > 10"
            v-model:current-page="tablePage"
            :page-size="10"
            :total="groups.length"
            layout="prev, pager, next"
            small
          />
        </article>
      </div>
    </template>
  </section>
</template>

<style scoped>
.history-panel {
  margin-top: 24px;
}
.history-muted {
  font-size: 12px;
  color: #6e8277;
  line-height: 1.8;
}
.history-filters {
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
  margin: 20px 0;
}
.history-filters label {
  display: flex;
  flex-direction: column;
  gap: 8px;
  font-size: 12px;
  color: #647c6d;
  width: 180px;
}
.history-filters .history-date {
  width: 340px;
  max-width: 100%;
}
.history-date :deep(.el-date-editor) {
  width: 100%;
  box-sizing: border-box;
}
.history-stats {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
  margin-top: 22px;
}
.history-stats > div {
  background: #f4f8f5;
  border: 1px solid #e4ece6;
  border-radius: 12px;
  padding: 18px;
}
.history-stats span {
  display: block;
  color: #71877a;
  font-size: 12px;
}
.history-stats strong {
  display: block;
  margin-top: 10px;
  font-size: 24px;
  color: #315b48;
  overflow-wrap: anywhere;
}
.history-stats small,
.history-chart h3 small {
  font-size: 12px;
  font-weight: 400;
  color: #71877a;
}
.history-chart-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 18px;
}
.history-chart {
  min-width: 0;
  border: 1px solid #e4ece6;
  border-radius: 14px;
  padding: 18px;
  background: #fff;
}
.history-chart h3 {
  font-size: 15px;
  margin: 0 0 12px;
}
.history-chart-grid .history-chart {
  overflow-x: auto;
}
.history-chart svg {
  min-width: 520px;
  width: 100%;
  display: block;
  overflow: visible;
}
.history-chart svg text {
  font-size: 12px;
  fill: #71877a;
}
.history-grid {
  stroke: #e8efea;
  stroke-dasharray: 4 4;
}
.history-bottom-grid {
  display: grid;
  grid-template-columns: minmax(230px, 1fr) minmax(0, 2fr);
  gap: 18px;
  margin-top: 18px;
}
.history-donut {
  width: 150px;
  height: 150px;
  border-radius: 50%;
  display: grid;
  place-items: center;
  margin: 20px auto;
}
.history-donut > div {
  width: 108px;
  height: 108px;
  background: white;
  border-radius: 50%;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
}
.history-donut strong {
  font-size: 26px;
  color: #315b48;
}
.history-donut span {
  font-size: 12px;
  color: #71877a;
}
.history-legend {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 12px;
  font-size: 12px;
  color: #647c6d;
}
.history-legend i {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  margin-right: 6px;
}
.history-table :deep(.el-pagination) {
  margin-top: 12px;
  justify-content: flex-end;
}
@media (max-width: 1000px) {
  .history-chart-grid,
  .history-bottom-grid {
    grid-template-columns: 1fr;
  }
}
@media (max-width: 600px) {
  .history-stats {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .history-filters label {
    width: calc(50% - 7px);
  }
  .history-filters .history-date {
    width: 100%;
  }
  .history-chart {
    padding: 12px;
  }
  .history-stats strong {
    font-size: 20px;
  }
}
</style>
