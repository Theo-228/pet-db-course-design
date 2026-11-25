<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";
import { api, errorMessage, refreshCsrf } from "./api";
import HistoryPanel from "./components/HistoryPanel.vue";
const historyPanel = ref(null);

const identity = ref(null);
const workspaceId = ref(null);
const page = ref("overview");
const busy = ref(false);
const authMode = ref("login");
const authForm = reactive({ loginName: "", password: "", workspaceName: "" });
const data = reactive({
  pets: [],
  devices: [],
  spaces: [],
  measurements: [],
  metrics: [],
  rules: [],
  alerts: [],
  executions: [],
});
const petForm = reactive({
  name: "",
  species: "猫",
  breed: "",
  sex: "UNKNOWN",
  birthDate: "",
  status: "ACTIVE",
});
const deviceForm = reactive({
  name: "",
  serialNumber: "",
  kind: "SCALE",
  sharingPolicy: "DEDICATED",
  spaceId: null,
});
const healthForm = reactive({
  petId: null,
  kind: "OBSERVATION",
  occurredAt: "",
  note: "",
});
const measurementForm = reactive({
  sourceKind: "MANUAL",
  petId: null,
  deviceId: null,
  spaceId: null,
  sourceEventId: "",
  metricCode: "weight_kg",
  value: null,
  measuredAt: "",
  periodStartedAt: "",
});
const ruleForm = reactive({
  name: "",
  metricCode: "weight_kg",
  comparator: "GT",
  threshold: null,
  sourceDeviceId: null,
  petId: null,
  actionKind: "ALERT",
  targetDeviceId: null,
  commandType: "PING",
  amount: null,
  severity: "WARNING",
  cooldownSeconds: 300,
});
const petDialog = ref(false);
const deviceDialog = ref(false);
const editingPetId = ref(null);
const editingDeviceId = ref(null);
const healthDialog = ref(false);
const measurementDialog = ref(false);
const ruleDialog = ref(false);
const bindingsDialog = ref(false);
const selectedDevice = ref(null);
const bindings = ref([]);
const healthRecords = ref([]);
const petReport = ref(null);
const selectedPet = ref(null);
const workspace = computed(() =>
  identity.value?.workspaces.find((x) => x.workspaceId === workspaceId.value),
);
const openAlerts = computed(() =>
  data.alerts.filter((x) => x.status === "OPEN"),
);
const activePets = computed(() =>
  data.pets.filter((x) => x.status !== "RETIRED"),
);
const onlineDevices = computed(() =>
  data.devices.filter((x) => x.status === "ONLINE"),
);
const base = computed(() => `/workspaces/${workspaceId.value}`);
const nav = [
  ["overview", "总览", "⌂"],
  ["pets", "宠物档案", "◈"],
  ["devices", "智能设备", "▣"],
  ["measurements", "测量数据", "◷"],
  ["automation", "自动化中心", "⚡"],
  ["ai", "AI 接口", "✧"],
];
const metricName = (code) =>
  data.metrics.find((x) => x.code === code)?.label || code;
const localDate = (value) =>
  value ? new Date(value).toLocaleString("zh-CN") : "—";
const instant = (value) => (value ? new Date(value).toISOString() : null);
const freshDateTime = () =>
  new Date(Date.now() - new Date().getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);

async function attempt(fn) {
  try {
    busy.value = true;
    await fn();
  } catch (error) {
    ElMessage.error(errorMessage(error));
  } finally {
    busy.value = false;
  }
}

async function load() {
  if (!workspaceId.value) return;
  const b = base.value;
  const [
    pets,
    devices,
    spaces,
    measurements,
    metrics,
    rules,
    alerts,
    executions,
  ] = await Promise.all([
    api("get", `${b}/pets`),
    api("get", `${b}/devices`),
    api("get", `${b}/spaces`),
    api("get", `${b}/measurements`),
    api("get", "/metrics"),
    api("get", `${b}/rules`),
    api("get", `${b}/alerts`),
    api("get", `${b}/executions`),
  ]);
  Object.assign(data, {
    pets,
    devices,
    spaces,
    measurements,
    metrics,
    rules,
    alerts,
    executions,
  });
}

async function authenticate() {
  await attempt(async () => {
    const path = authMode.value === "login" ? "/auth/login" : "/auth/register";
    identity.value = await api(
      "post",
      path,
      authMode.value === "login"
        ? { loginName: authForm.loginName, password: authForm.password }
        : { ...authForm },
    );
    workspaceId.value = identity.value.workspaces[0]?.workspaceId;
    await load();
    ElMessage.success("欢迎进入 PetOS");
  });
}
async function logout() {
  await attempt(async () => {
    await api("post", "/auth/logout");
    identity.value = null;
    workspaceId.value = null;
    await refreshCsrf();
  });
}
async function changeWorkspace(id) {
  workspaceId.value = id;
  await attempt(load);
}
async function createWorkspace() {
  try {
    const { value } = await ElMessageBox.prompt(
      "输入工作空间名称",
      "新建工作空间",
      {
        inputPattern: /\S/,
        inputErrorMessage: "请输入名称",
      },
    );
    await attempt(async () => {
      const created = await api("post", "/workspaces", { name: value });
      identity.value = await api("get", "/auth/me");
      workspaceId.value = created.id;
      await load();
      ElMessage.success("工作空间已创建");
    });
  } catch {
    /* cancelled */
  }
}

async function createSpace() {
  try {
    const { value } = await ElMessageBox.prompt("输入区域名称", "新建区域", {
      inputPattern: /\S/,
      inputErrorMessage: "请输入名称",
    });
    await attempt(async () => {
      await api("post", `${base.value}/spaces`, { name: value });
      await load();
      ElMessage.success("区域已创建");
    });
  } catch {
    /* cancelled */
  }
}
function openPetCreate() {
  editingPetId.value = null;
  Object.assign(petForm, {
    name: "",
    species: "猫",
    breed: "",
    sex: "UNKNOWN",
    birthDate: "",
    status: "ACTIVE",
  });
  petDialog.value = true;
}
function openPetEdit(pet) {
  editingPetId.value = pet.id;
  Object.assign(petForm, {
    name: pet.name,
    species: pet.species,
    breed: pet.breed || "",
    sex: pet.sex,
    birthDate: pet.birthDate || "",
    status: pet.status,
  });
  petDialog.value = true;
}
async function savePet() {
  await attempt(async () => {
    await api(
      editingPetId.value ? "put" : "post",
      editingPetId.value
        ? `${base.value}/pets/${editingPetId.value}`
        : `${base.value}/pets`,
      {
        ...petForm,
        birthDate: petForm.birthDate || null,
      },
    );
    petDialog.value = false;
    await load();
    ElMessage.success(editingPetId.value ? "档案已更新" : "宠物已添加");
  });
}
async function retirePet(pet) {
  try {
    await ElMessageBox.confirm(
      `归档 ${pet.name}？历史测量仍会保留。`,
      "确认归档",
    );
  } catch {
    return;
  }
  await attempt(async () => {
    await api("post", `${base.value}/pets/${pet.id}/retire`);
    await load();
  });
}
async function showHealth(pet) {
  selectedPet.value = pet;
  healthForm.petId = pet.id;
  healthForm.occurredAt = freshDateTime();
  await attempt(async () => {
    const [records, report] = await Promise.all([
      api("get", `${base.value}/pets/${pet.id}/health-records`),
      api("get", `${base.value}/pets/${pet.id}/report`),
    ]);
    healthRecords.value = records;
    petReport.value = report;
    healthDialog.value = true;
  });
}
async function addHealth() {
  await attempt(async () => {
    await api("post", `${base.value}/pets/${healthForm.petId}/health-records`, {
      kind: healthForm.kind,
      occurredAt: instant(healthForm.occurredAt),
      note: healthForm.note,
    });
    healthRecords.value = await api(
      "get",
      `${base.value}/pets/${healthForm.petId}/health-records`,
    );
    healthForm.note = "";
    ElMessage.success("健康记录已添加");
  });
}
function openDeviceCreate() {
  editingDeviceId.value = null;
  Object.assign(deviceForm, {
    name: "",
    serialNumber: "",
    kind: "SCALE",
    sharingPolicy: "DEDICATED",
    spaceId: null,
  });
  deviceDialog.value = true;
}
function openDeviceEdit(device) {
  editingDeviceId.value = device.id;
  Object.assign(deviceForm, {
    name: device.name,
    serialNumber: device.serialNumber,
    kind: device.kind,
    sharingPolicy: device.sharingPolicy,
    spaceId: device.spaceId,
  });
  deviceDialog.value = true;
}
async function saveDevice() {
  await attempt(async () => {
    if (editingDeviceId.value)
      await api("put", `${base.value}/devices/${editingDeviceId.value}`, {
        name: deviceForm.name,
        spaceId: deviceForm.spaceId,
      });
    else await api("post", `${base.value}/devices`, { ...deviceForm });
    deviceDialog.value = false;
    await load();
    ElMessage.success(editingDeviceId.value ? "设备已更新" : "设备已添加");
  });
}
async function deviceStatus(device, status) {
  await attempt(async () => {
    await api("post", `${base.value}/devices/${device.id}/status`, { status });
    await load();
  });
}
async function showBindings(device) {
  selectedDevice.value = device;
  await attempt(async () => {
    bindings.value = await api(
      "get",
      `${base.value}/devices/${device.id}/bindings`,
    );
    bindingsDialog.value = true;
  });
}
async function bindPet(petId) {
  await attempt(async () => {
    await api(
      "post",
      `${base.value}/devices/${selectedDevice.value.id}/bindings`,
      { petId },
    );
    bindings.value = await api(
      "get",
      `${base.value}/devices/${selectedDevice.value.id}/bindings`,
    );
    ElMessage.success("绑定已建立");
  });
}
async function unbind(bindingId) {
  await attempt(async () => {
    await api(
      "post",
      `${base.value}/devices/${selectedDevice.value.id}/bindings/${bindingId}/close`,
    );
    bindings.value = await api(
      "get",
      `${base.value}/devices/${selectedDevice.value.id}/bindings`,
    );
  });
}
async function simulate(device) {
  try {
    const commandType =
      device.kind === "SCALE"
        ? "TARE"
        : ["FEEDER", "WATERER"].includes(device.kind)
          ? "DISPENSE"
          : "PING";
    let payload = {};
    if (commandType === "DISPENSE") {
      const { value } = await ElMessageBox.prompt(
        "模拟投放量",
        "设备指令（仅模拟）",
        { inputType: "number", inputValue: "25" },
      );
      payload = { amount: Number(value) };
    }
    await attempt(async () => {
      await api("post", `${base.value}/devices/${device.id}/commands`, {
        commandType,
        payload,
      });
      ElMessage.success("模拟指令已记录");
    });
  } catch {
    /* cancelled */
  }
}
async function saveMeasurement() {
  await attempt(async () => {
    const manual = measurementForm.sourceKind === "MANUAL";
    await api("post", `${base.value}/measurements`, {
      sourceKind: measurementForm.sourceKind,
      petId: manual ? measurementForm.petId : null,
      deviceId: manual ? null : measurementForm.deviceId,
      spaceId: manual ? null : measurementForm.spaceId,
      sourceEventId: manual ? null : measurementForm.sourceEventId,
      metricCode: measurementForm.metricCode,
      value: measurementForm.value,
      measuredAt: instant(measurementForm.measuredAt),
      periodStartedAt:
        measurementForm.metricCode === "activity_minutes"
          ? instant(measurementForm.periodStartedAt)
          : null,
    });
    measurementDialog.value = false;
    await load();
    ElMessage.success("测量已写入；规则已评估");
  });
}
function newMeasurement() {
  measurementForm.measuredAt = freshDateTime();
  measurementDialog.value = true;
}
async function reviseAttribution(row) {
  try {
    const { value } = await ElMessageBox.prompt(
      "输入宠物 ID；留空表示未知归属",
      "修订测量归属",
      { inputValue: row.petId || "" },
    );
    const petId = value.trim() ? Number(value) : null;
    const reason = await ElMessageBox.prompt("请输入修订理由", "审计记录", {
      inputPattern: /\S/,
      inputErrorMessage: "理由不能为空",
    });
    await attempt(async () => {
      await api("post", `${base.value}/measurements/${row.id}/attributions`, {
        petId,
        reason: reason.value,
      });
      await load();
    });
  } catch {
    /* cancelled */
  }
}
async function saveRule() {
  await attempt(async () => {
    const command = ruleForm.actionKind === "DEVICE_COMMAND";
    await api("post", `${base.value}/rules`, {
      name: ruleForm.name,
      metricCode: ruleForm.metricCode,
      comparator: ruleForm.comparator,
      threshold: ruleForm.threshold,
      sourceDeviceId: ruleForm.sourceDeviceId,
      petId: ruleForm.petId,
      actionKind: ruleForm.actionKind,
      targetDeviceId: command ? ruleForm.targetDeviceId : null,
      actionPayload: command
        ? {
            command_type: ruleForm.commandType,
            ...(ruleForm.commandType === "DISPENSE"
              ? { amount: ruleForm.amount }
              : {}),
          }
        : {},
      severity: ruleForm.severity,
      cooldownSeconds: Number(ruleForm.cooldownSeconds),
    });
    ruleDialog.value = false;
    await load();
    ElMessage.success("规则已创建");
  });
}
async function toggleRule(rule) {
  await attempt(async () => {
    await api("post", `${base.value}/rules/${rule.id}/enabled`, {
      enabled: !rule.enabled,
    });
    await load();
  });
}
async function resolveAlert(alert) {
  await attempt(async () => {
    await api("post", `${base.value}/alerts/${alert.id}/resolve`);
    await load();
  });
}
onMounted(async () => {
  try {
    await refreshCsrf();
    identity.value = await api("get", "/auth/me");
    workspaceId.value = identity.value.workspaces[0]?.workspaceId;
    await load();
  } catch {
    identity.value = null;
  }
});
</script>

<template>
  <div v-if="!identity" class="auth-shell">
    <div class="auth-story">
      <div class="brand-mark">P</div>
      <p class="eyebrow">PETOS · CONNECTED CARE</p>
      <h1>更清晰地了解<br />每一个小生命。</h1>
      <p>宠物健康、智能设备与自动化规则，在同一工作空间中有序协作。</p>
      <div class="story-note">为家庭与猫咖设计的统一管理系统</div>
    </div>
    <div class="auth-card">
      <p class="eyebrow">WELCOME TO PETOS</p>
      <h2>{{ authMode === "login" ? "登录工作空间" : "创建工作空间" }}</h2>
      <p class="muted">
        {{
          authMode === "login"
            ? "继续管理你的宠物与设备"
            : "从一个安全的工作空间开始"
        }}
      </p>
      <el-form
        :model="authForm"
        label-position="top"
        @submit.prevent="authenticate"
        ><el-form-item label="账号"
          ><el-input
            v-model="authForm.loginName"
            placeholder="输入账号"
            size="large" /></el-form-item
        ><el-form-item label="密码"
          ><el-input
            v-model="authForm.password"
            type="password"
            show-password
            placeholder="输入密码"
            size="large" /></el-form-item
        ><el-form-item v-if="authMode === 'register'" label="工作空间名称"
          ><el-input
            v-model="authForm.workspaceName"
            placeholder="例如：我和小猫的家"
            size="large" /></el-form-item
        ><el-button
          class="full-button"
          type="primary"
          native-type="submit"
          size="large"
          :loading="busy"
          >{{ authMode === "login" ? "登录" : "注册并开始" }}</el-button
        ></el-form
      >
      <p class="switch-auth">
        {{ authMode === "login" ? "还没有账号？" : "已有账号？" }}
        <a @click="authMode = authMode === 'login' ? 'register' : 'login'">{{
          authMode === "login" ? "创建账号" : "返回登录"
        }}</a>
      </p>
    </div>
  </div>
  <div v-else class="app-shell">
    <aside class="sidebar">
      <div class="logo">
        <span class="brand-mark small">P</span
        ><span>PetOS<small>CONNECTED CARE</small></span>
      </div>
      <div class="workspace-pill">
        <span class="workspace-icon">⌂</span>
        <div>
          <small>当前工作空间</small
          ><strong>{{ workspace?.workspaceName }}</strong>
        </div>
      </div>
      <div class="nav-caption">WORKSPACE</div>
      <nav>
        <button
          v-for="item in nav"
          :key="item[0]"
          :class="['nav-item', { active: page === item[0] }]"
          @click="page = item[0]"
        >
          <span class="nav-icon">{{ item[2] }}</span
          >{{ item[1]
          }}<span
            v-if="item[0] === 'automation' && openAlerts.length"
            class="nav-count"
            >{{ openAlerts.length }}</span
          >
        </button>
      </nav>
      <div class="sidebar-bottom">
        <p>设备动作均为模拟执行。<br />AI 功能仅预留接口。</p>
        <button @click="logout">退出登录 ↗</button>
      </div>
    </aside>
    <div class="main-area">
      <header class="topbar">
        <div class="breadcrumbs">
          工作空间 <span>/</span> {{ nav.find((x) => x[0] === page)?.[1] }}
        </div>
        <div class="topbar-actions">
          <el-select
            v-if="identity.workspaces.length > 1"
            :model-value="workspaceId"
            @change="changeWorkspace"
            style="width: 180px"
            ><el-option
              v-for="w in identity.workspaces"
              :key="w.workspaceId"
              :label="w.workspaceName"
              :value="w.workspaceId" /></el-select
          ><el-button text @click="createWorkspace">＋ 工作空间</el-button>
          <el-button text @click="attempt(load)">刷新数据 ↻</el-button>
          <div class="avatar">
            {{ identity.loginName.slice(0, 1).toUpperCase() }}
          </div>
        </div>
      </header>
      <main class="content">
        <template v-if="page === 'overview'"
          ><div class="page-intro">
            <div>
              <p class="eyebrow">YOUR WORKSPACE AT A GLANCE</p>
              <h1>
                你好，{{ identity.loginName }} <span class="wave">✦</span>
              </h1>
              <p>从一个清楚的总览开始，及时掌握宠物、设备和提醒。</p>
            </div>
            <el-button type="primary" @click="newMeasurement"
              >＋ 记录测量</el-button
            >
          </div>
          <div class="stats">
            <div class="stat-card">
              <span>宠物档案</span><strong>{{ activePets.length }}</strong
              ><small>正在管理</small>
            </div>
            <div class="stat-card">
              <span>在线设备</span
              ><strong
                >{{ onlineDevices.length }}
                <em>/ {{ data.devices.length }}</em></strong
              ><small>模拟连接状态</small>
            </div>
            <div class="stat-card accent">
              <span>待处理提醒</span><strong>{{ openAlerts.length }}</strong
              ><small>来自自动化规则</small>
            </div>
            <div class="stat-card">
              <span>已记录测量</span
              ><strong>{{ data.measurements.length }}</strong
              ><small>最近 200 条</small>
            </div>
          </div>
          <div class="overview-grid">
            <section class="panel">
              <div class="panel-head">
                <div>
                  <p class="eyebrow">RECENT ACTIVITY</p>
                  <h2>最新测量</h2>
                </div>
                <el-button text @click="page = 'measurements'"
                  >查看全部 →</el-button
                >
              </div>
              <el-empty
                v-if="!data.measurements.length"
                description="还没有测量记录"
              />
              <div
                v-for="m in data.measurements.slice(0, 5)"
                :key="m.id"
                class="activity-row"
              >
                <div class="activity-icon">◷</div>
                <div>
                  <strong>{{ metricName(m.metricCode) }}</strong
                  ><small
                    >{{
                      m.petId
                        ? data.pets.find((p) => p.id === m.petId)?.name ||
                          "宠物"
                        : "未归属/环境数据"
                    }}
                    · {{ localDate(m.measuredAt) }}</small
                  >
                </div>
                <b
                  >{{ m.value }}
                  {{
                    data.metrics.find((x) => x.code === m.metricCode)?.unit
                  }}</b
                >
              </div>
            </section>
            <section class="panel">
              <div class="panel-head">
                <div>
                  <p class="eyebrow">NEEDS ATTENTION</p>
                  <h2>待处理提醒</h2>
                </div>
                <el-button text @click="page = 'automation'"
                  >查看全部 →</el-button
                >
              </div>
              <el-empty
                v-if="!openAlerts.length"
                description="当前没有待处理提醒"
              />
              <div
                v-for="a in openAlerts.slice(0, 5)"
                :key="a.id"
                class="alert-row"
              >
                <span
                  :class="['severity-dot', a.severity.toLowerCase()]"
                ></span>
                <div>
                  <strong>{{ a.title }}</strong
                  ><small>{{ localDate(a.createdAt) }}</small>
                </div>
                <el-tag
                  :type="a.severity === 'CRITICAL' ? 'danger' : 'warning'"
                  size="small"
                  >{{ a.severity }}</el-tag
                >
              </div>
            </section>
          </div></template
        >
        <template v-else-if="page === 'pets'"
          ><div class="page-intro">
            <div>
              <p class="eyebrow">PET PROFILES</p>
              <h1>宠物档案</h1>
              <p>把身份信息、健康记录与设备数据串联起来。</p>
            </div>
            <el-button type="primary" @click="openPetCreate"
              >＋ 添加宠物</el-button
            >
          </div>
          <div class="panel">
            <el-empty v-if="!data.pets.length" description="还没有宠物档案" />
            <div class="pet-grid">
              <div v-for="pet in data.pets" :key="pet.id" class="pet-card">
                <div class="pet-avatar">
                  {{
                    pet.species === "猫"
                      ? "🐈"
                      : pet.species === "狗"
                        ? "🐕"
                        : "🐾"
                  }}
                </div>
                <div class="pet-card-main">
                  <h3>
                    {{ pet.name }}
                    <el-tag
                      size="small"
                      :type="pet.status === 'RETIRED' ? 'info' : 'success'"
                      >{{ pet.status }}</el-tag
                    >
                  </h3>
                  <p>
                    {{ pet.species }} · {{ pet.breed || "品种未填写" }} ·
                    {{ pet.sex }}
                  </p>
                  <small>档案编号 #{{ pet.id }}</small>
                </div>
                <div class="pet-actions">
                  <el-button text @click="historyPanel?.select(pet.id)"
                    >数据趋势</el-button
                  ><el-button text @click="showHealth(pet)">健康记录</el-button
                  ><el-button
                    v-if="pet.status !== 'RETIRED'"
                    text
                    @click="openPetEdit(pet)"
                    >编辑</el-button
                  ><el-button
                    v-if="pet.status !== 'RETIRED'"
                    text
                    type="danger"
                    @click="retirePet(pet)"
                    >归档</el-button
                  >
                </div>
              </div>
            </div>
          </div></template
        >
        <template v-else-if="page === 'devices'"
          ><div class="page-intro">
            <div>
              <p class="eyebrow">CONNECTED DEVICES</p>
              <h1>智能设备</h1>
              <p>设备绑定与模拟指令。系统不连接真实硬件。</p>
            </div>
            <div>
              <el-button @click="createSpace">＋ 新建区域</el-button
              ><el-button type="primary" @click="openDeviceCreate"
                >＋ 添加设备</el-button
              >
            </div>
          </div>
          <div class="panel">
            <el-empty
              v-if="!data.devices.length"
              description="还没有设备"
            /><el-table v-else :data="data.devices"
              ><el-table-column
                prop="name"
                label="设备"
                min-width="150"
              /><el-table-column
                prop="kind"
                label="类型"
                width="130"
              /><el-table-column
                prop="serialNumber"
                label="序列号"
                min-width="150"
              /><el-table-column label="归属方式" width="120"
                ><template #default="{ row }">{{
                  row.sharingPolicy === "SHARED" ? "共享" : "专属"
                }}</template></el-table-column
              ><el-table-column label="状态" width="110"
                ><template #default="{ row }"
                  ><el-tag
                    :type="row.status === 'ONLINE' ? 'success' : 'info'"
                    >{{ row.status }}</el-tag
                  ></template
                ></el-table-column
              ><el-table-column label="操作" min-width="240"
                ><template #default="{ row }"
                  ><el-button link @click="historyPanel?.select(row.id)"
                    >历史数据</el-button
                  ><el-button link @click="showBindings(row)">绑定</el-button
                  ><el-button link @click="openDeviceEdit(row)">编辑</el-button
                  ><el-button
                    link
                    @click="
                      deviceStatus(
                        row,
                        row.status === 'ONLINE' ? 'OFFLINE' : 'ONLINE',
                      )
                    "
                    >{{
                      row.status === "ONLINE" ? "置为离线" : "模拟上线"
                    }}</el-button
                  ><el-button
                    link
                    :disabled="row.status !== 'ONLINE'"
                    @click="simulate(row)"
                    >模拟指令</el-button
                  ></template
                ></el-table-column
              ></el-table
            >
          </div></template
        >
        <template v-else-if="page === 'measurements'"
          ><div class="page-intro">
            <div>
              <p class="eyebrow">MEASUREMENT JOURNAL</p>
              <h1>测量数据</h1>
              <p>原始记录不可修改；归属纠正会保留每次修订的审计轨迹。</p>
            </div>
            <el-button type="primary" @click="newMeasurement"
              >＋ 新增测量</el-button
            >
          </div>
          <div class="panel">
            <el-empty
              v-if="!data.measurements.length"
              description="暂无测量记录"
            /><el-table v-else :data="data.measurements"
              ><el-table-column label="时间" min-width="160"
                ><template #default="{ row }">{{
                  localDate(row.measuredAt)
                }}</template></el-table-column
              ><el-table-column label="指标" min-width="130"
                ><template #default="{ row }">{{
                  metricName(row.metricCode)
                }}</template></el-table-column
              ><el-table-column label="数值" width="120"
                ><template #default="{ row }"
                  ><strong>{{ row.value }}</strong>
                  {{
                    data.metrics.find((x) => x.code === row.metricCode)?.unit
                  }}</template
                ></el-table-column
              ><el-table-column label="宠物归属" min-width="130"
                ><template #default="{ row }">{{
                  row.petId
                    ? data.pets.find((p) => p.id === row.petId)?.name ||
                      `#${row.petId}`
                    : "未知 / 不适用"
                }}</template></el-table-column
              ><el-table-column
                prop="attributionMethod"
                label="归属依据"
                width="130"
              /><el-table-column label="来源" width="90"
                ><template #default="{ row }">{{
                  row.sourceKind === "MANUAL" ? "人工" : "设备"
                }}</template></el-table-column
              ><el-table-column label="操作" width="100"
                ><template #default="{ row }"
                  ><el-button
                    v-if="
                      row.sourceKind === 'DEVICE' &&
                      data.metrics.find((x) => x.code === row.metricCode)
                        ?.scope === 'PET'
                    "
                    link
                    @click="reviseAttribution(row)"
                    >修订归属</el-button
                  ></template
                ></el-table-column
              ></el-table
            >
          </div></template
        >
        <template v-else-if="page === 'automation'"
          ><div class="page-intro">
            <div>
              <p class="eyebrow">AUTOMATION CENTER</p>
              <h1>自动化中心</h1>
              <p>基于明确阈值的规则引擎；每次执行、告警和设备指令都有记录。</p>
            </div>
            <el-button type="primary" @click="ruleDialog = true"
              >＋ 新建规则</el-button
            >
          </div>
          <el-tabs
            ><el-tab-pane label="规则"
              ><div class="panel">
                <el-empty
                  v-if="!data.rules.length"
                  description="还没有自动化规则"
                /><el-table v-else :data="data.rules"
                  ><el-table-column
                    prop="name"
                    label="规则名称"
                    min-width="170"
                  /><el-table-column label="条件" min-width="200"
                    ><template #default="{ row }"
                      >{{ metricName(row.metricCode) }} {{ row.comparator }}
                      {{ row.threshold }}</template
                    ></el-table-column
                  ><el-table-column label="动作" width="145"
                    ><template #default="{ row }">{{
                      row.actionKind === "ALERT" ? "创建提醒" : "模拟设备指令"
                    }}</template></el-table-column
                  ><el-table-column
                    prop="cooldownSeconds"
                    label="冷却（秒）"
                    width="110"
                  /><el-table-column label="状态" width="100"
                    ><template #default="{ row }"
                      ><el-tag :type="row.enabled ? 'success' : 'info'">{{
                        row.enabled ? "启用" : "停用"
                      }}</el-tag></template
                    ></el-table-column
                  ><el-table-column label="操作" width="100"
                    ><template #default="{ row }"
                      ><el-button link @click="toggleRule(row)">{{
                        row.enabled ? "停用" : "启用"
                      }}</el-button></template
                    ></el-table-column
                  ></el-table
                >
              </div></el-tab-pane
            ><el-tab-pane
              :label="`提醒 ${openAlerts.length ? `(${openAlerts.length})` : ''}`"
              ><div class="panel">
                <el-empty
                  v-if="!data.alerts.length"
                  description="暂无提醒"
                /><el-table v-else :data="data.alerts"
                  ><el-table-column
                    prop="title"
                    label="标题"
                    min-width="180"
                  /><el-table-column
                    prop="details"
                    label="详情"
                    min-width="220"
                  /><el-table-column
                    prop="severity"
                    label="级别"
                    width="100"
                  /><el-table-column label="时间" width="180"
                    ><template #default="{ row }">{{
                      localDate(row.createdAt)
                    }}</template></el-table-column
                  ><el-table-column
                    prop="status"
                    label="状态"
                    width="100"
                  /><el-table-column label="操作" width="100"
                    ><template #default="{ row }"
                      ><el-button
                        v-if="row.status === 'OPEN'"
                        link
                        @click="resolveAlert(row)"
                        >标记已处理</el-button
                      ></template
                    ></el-table-column
                  ></el-table
                >
              </div></el-tab-pane
            ><el-tab-pane label="执行记录"
              ><div class="panel">
                <el-empty
                  v-if="!data.executions.length"
                  description="暂无执行记录"
                /><el-table v-else :data="data.executions"
                  ><el-table-column
                    prop="ruleId"
                    label="规则 ID"
                    width="100" /><el-table-column
                    prop="measurementId"
                    label="测量 ID"
                    width="100" /><el-table-column
                    prop="actionKind"
                    label="动作"
                    min-width="140" /><el-table-column
                    prop="status"
                    label="结果"
                    width="110" /><el-table-column
                    label="触发时间"
                    min-width="180"
                    ><template #default="{ row }">{{
                      localDate(row.triggeredAt)
                    }}</template></el-table-column
                  ><el-table-column
                    prop="errorMessage"
                    label="说明"
                    min-width="180"
                /></el-table></div></el-tab-pane></el-tabs
        ></template>
        <template v-else-if="page === 'ai'"
          ><div class="page-intro">
            <div>
              <p class="eyebrow">FUTURE INTEGRATIONS</p>
              <h1>AI 能力接口</h1>
              <p>保留集成位置，不展示伪造的智能分析结果。</p>
            </div>
          </div>
          <div class="ai-grid">
            <div class="panel ai-card">
              <div class="ai-symbol">✦</div>
              <h2>宠物健康分析</h2>
              <p>
                未来可结合真实模型分析宠物档案、健康记录和测量趋势。当前仅提供后端接口，占位返回
                HTTP 501。
              </p>
              <el-tag type="info">尚未接入模型</el-tag>
            </div>
            <div class="panel ai-card">
              <div class="ai-symbol">◎</div>
              <h2>全局智能助手</h2>
              <p>
                未来可接入经过授权的数据查询和知识库。当前不生成答复、不执行数据库自然语言查询。
              </p>
              <el-tag type="info">尚未接入模型</el-tag>
            </div>
          </div></template
        >
        <HistoryPanel
          v-if="page === 'pets' || page === 'devices'"
          :key="page"
          ref="historyPanel"
          :workspace-id="workspaceId"
          :kind="page === 'pets' ? 'pet' : 'device'"
          :entities="page === 'pets' ? data.pets : data.devices"
          :metrics="data.metrics"
        />
      </main>
    </div>
  </div>

  <el-dialog
    v-model="petDialog"
    :title="editingPetId ? '编辑宠物' : '添加宠物'"
    width="500"
    ><el-form :model="petForm" label-position="top"
      ><el-form-item label="名字"
        ><el-input v-model="petForm.name" /></el-form-item
      ><el-form-item label="物种"
        ><el-input v-model="petForm.species" /></el-form-item
      ><el-form-item label="品种"
        ><el-input v-model="petForm.breed" /></el-form-item
      ><el-form-item label="性别"
        ><el-select v-model="petForm.sex"
          ><el-option label="未知" value="UNKNOWN" /><el-option
            label="雌性"
            value="FEMALE" /><el-option
            label="雄性"
            value="MALE" /></el-select></el-form-item
      ><el-form-item label="出生日期"
        ><el-date-picker
          v-model="petForm.birthDate"
          type="date"
          value-format="YYYY-MM-DD"
          style="width: 100%" /></el-form-item></el-form
    ><template #footer
      ><el-button @click="petDialog = false">取消</el-button
      ><el-button type="primary" :loading="busy" @click="savePet"
        >保存</el-button
      ></template
    ></el-dialog
  >
  <el-dialog
    v-model="healthDialog"
    :title="`${selectedPet?.name || ''} · 健康记录`"
    width="650"
    ><el-form :model="healthForm" label-position="top"
      ><div class="form-grid">
        <el-form-item label="记录类型"
          ><el-select v-model="healthForm.kind"
            ><el-option label="日常观察" value="OBSERVATION" /><el-option
              label="疫苗"
              value="VACCINATION" /><el-option
              label="治疗"
              value="TREATMENT" /><el-option
              label="就诊"
              value="VET_VISIT" /></el-select></el-form-item
        ><el-form-item label="发生时间"
          ><el-input v-model="healthForm.occurredAt" type="datetime-local"
        /></el-form-item>
      </div>
      <el-form-item label="说明"
        ><el-input
          v-model="healthForm.note"
          type="textarea"
          :rows="2" /></el-form-item
      ><el-button type="primary" @click="addHealth"
        >添加记录</el-button
      ></el-form
    ><el-divider /><el-empty
      v-if="!healthRecords.length"
      description="暂无记录"
    />
    <div v-for="record in healthRecords" :key="record.id" class="journal-row">
      <strong>{{ record.kind }}</strong
      ><span>{{ record.note }}</span
      ><small>{{ localDate(record.occurredAt) }}</small>
    </div></el-dialog
  >
  <el-dialog
    v-model="deviceDialog"
    :title="editingDeviceId ? '编辑设备' : '添加设备'"
    width="500"
    ><el-form :model="deviceForm" label-position="top"
      ><el-form-item label="设备名称"
        ><el-input v-model="deviceForm.name" /></el-form-item
      ><el-form-item label="序列号"
        ><el-input
          v-model="deviceForm.serialNumber"
          :disabled="!!editingDeviceId"
      /></el-form-item>
      <div class="form-grid">
        <el-form-item label="设备类型"
          ><el-select v-model="deviceForm.kind" :disabled="!!editingDeviceId"
            ><el-option label="项圈" value="COLLAR" /><el-option
              label="体重秤"
              value="SCALE" /><el-option
              label="喂食器"
              value="FEEDER" /><el-option
              label="饮水器"
              value="WATERER" /><el-option
              label="环境传感器"
              value="ENVIRONMENT" /></el-select></el-form-item
        ><el-form-item label="绑定策略"
          ><el-select
            v-model="deviceForm.sharingPolicy"
            :disabled="!!editingDeviceId"
            ><el-option label="专属" value="DEDICATED" /><el-option
              label="共享"
              value="SHARED" /></el-select
        ></el-form-item>
      </div>
      <el-form-item label="所在区域"
        ><el-select v-model="deviceForm.spaceId" clearable placeholder="可选"
          ><el-option
            v-for="space in data.spaces"
            :key="space.id"
            :label="space.name"
            :value="space.id" /></el-select></el-form-item></el-form
    ><template #footer
      ><el-button @click="deviceDialog = false">取消</el-button
      ><el-button type="primary" @click="saveDevice">保存</el-button></template
    ></el-dialog
  >
  <el-dialog
    v-model="bindingsDialog"
    :title="`${selectedDevice?.name || ''} · 宠物绑定`"
    width="570"
    ><p class="muted">共享设备的测量不会仅因绑定而自动判定宠物身份。</p>
    <el-select
      placeholder="选择宠物并建立绑定"
      style="width: 100%"
      @change="bindPet"
      ><el-option
        v-for="pet in activePets"
        :key="pet.id"
        :label="pet.name"
        :value="pet.id" /></el-select
    ><el-divider /><el-empty v-if="!bindings.length" description="暂无绑定" />
    <div v-for="binding in bindings" :key="binding.id" class="journal-row">
      <strong>{{ binding.petName }}</strong
      ><span
        >{{ localDate(binding.boundAt) }} →
        {{ binding.unboundAt ? localDate(binding.unboundAt) : "当前" }}</span
      ><el-button v-if="!binding.unboundAt" link @click="unbind(binding.id)"
        >解除</el-button
      >
    </div></el-dialog
  >
  <el-dialog v-model="measurementDialog" title="新增测量" width="570"
    ><el-form :model="measurementForm" label-position="top"
      ><div class="form-grid">
        <el-form-item label="来源"
          ><el-select v-model="measurementForm.sourceKind"
            ><el-option label="人工" value="MANUAL" /><el-option
              label="设备模拟上报"
              value="DEVICE" /></el-select></el-form-item
        ><el-form-item label="指标"
          ><el-select v-model="measurementForm.metricCode"
            ><el-option
              v-for="metric in data.metrics.filter(
                (x) =>
                  measurementForm.sourceKind === 'DEVICE' || x.scope === 'PET',
              )"
              :key="metric.code"
              :label="`${metric.label} (${metric.unit})`"
              :value="metric.code" /></el-select
        ></el-form-item>
      </div>
      <el-form-item v-if="measurementForm.sourceKind === 'MANUAL'" label="宠物"
        ><el-select v-model="measurementForm.petId" placeholder="选择宠物"
          ><el-option
            v-for="pet in activePets"
            :key="pet.id"
            :label="pet.name"
            :value="pet.id" /></el-select></el-form-item
      ><template v-else
        ><div class="form-grid">
          <el-form-item label="设备"
            ><el-select v-model="measurementForm.deviceId"
              ><el-option
                v-for="device in data.devices"
                :key="device.id"
                :label="device.name"
                :value="device.id" /></el-select></el-form-item
          ><el-form-item label="事件编号（去重）"
            ><el-input
              v-model="measurementForm.sourceEventId"
              placeholder="例如 sim-001"
          /></el-form-item>
        </div>
        <el-form-item
          v-if="
            data.metrics.find((x) => x.code === measurementForm.metricCode)
              ?.scope === 'SPACE'
          "
          label="区域"
          ><el-select v-model="measurementForm.spaceId"
            ><el-option
              v-for="space in data.spaces"
              :key="space.id"
              :label="space.name"
              :value="space.id" /></el-select></el-form-item
      ></template>
      <div class="form-grid">
        <el-form-item label="数值"
          ><el-input-number
            v-model="measurementForm.value"
            :precision="2"
            :controls="false"
            style="width: 100%" /></el-form-item
        ><el-form-item label="测量时间"
          ><el-input v-model="measurementForm.measuredAt" type="datetime-local"
        /></el-form-item>
      </div>
      <el-form-item
        v-if="measurementForm.metricCode === 'activity_minutes'"
        label="观察区间开始"
        ><el-input
          v-model="measurementForm.periodStartedAt"
          type="datetime-local" /></el-form-item></el-form
    ><template #footer
      ><el-button @click="measurementDialog = false">取消</el-button
      ><el-button type="primary" @click="saveMeasurement"
        >写入测量</el-button
      ></template
    ></el-dialog
  >
  <el-dialog v-model="ruleDialog" title="新建自动化规则" width="600"
    ><el-form :model="ruleForm" label-position="top"
      ><el-form-item label="规则名称"
        ><el-input v-model="ruleForm.name" placeholder="例如：体重过高提醒"
      /></el-form-item>
      <div class="form-grid">
        <el-form-item label="测量指标"
          ><el-select v-model="ruleForm.metricCode"
            ><el-option
              v-for="metric in data.metrics"
              :key="metric.code"
              :label="metric.label"
              :value="metric.code" /></el-select></el-form-item
        ><el-form-item label="比较方式"
          ><el-select v-model="ruleForm.comparator"
            ><el-option label="大于" value="GT" /><el-option
              label="大于等于"
              value="GTE" /><el-option label="小于" value="LT" /><el-option
              label="小于等于"
              value="LTE" /></el-select
        ></el-form-item>
      </div>
      <el-form-item label="阈值"
        ><el-input-number
          v-model="ruleForm.threshold"
          :controls="false"
          style="width: 100%"
      /></el-form-item>
      <div class="form-grid">
        <el-form-item label="限定来源设备（可选）"
          ><el-select v-model="ruleForm.sourceDeviceId" clearable
            ><el-option
              v-for="device in data.devices"
              :key="device.id"
              :label="device.name"
              :value="device.id" /></el-select></el-form-item
        ><el-form-item label="限定宠物（可选）"
          ><el-select v-model="ruleForm.petId" clearable
            ><el-option
              v-for="pet in activePets"
              :key="pet.id"
              :label="pet.name"
              :value="pet.id" /></el-select
        ></el-form-item>
      </div>
      <div class="form-grid">
        <el-form-item label="动作"
          ><el-select v-model="ruleForm.actionKind"
            ><el-option label="创建提醒" value="ALERT" /><el-option
              label="模拟设备指令"
              value="DEVICE_COMMAND" /></el-select></el-form-item
        ><el-form-item label="提醒等级"
          ><el-select v-model="ruleForm.severity"
            ><el-option label="普通" value="INFO" /><el-option
              label="警告"
              value="WARNING" /><el-option
              label="严重"
              value="CRITICAL" /></el-select
        ></el-form-item>
      </div>
      <template v-if="ruleForm.actionKind === 'DEVICE_COMMAND'"
        ><div class="form-grid">
          <el-form-item label="目标设备"
            ><el-select v-model="ruleForm.targetDeviceId"
              ><el-option
                v-for="device in data.devices"
                :key="device.id"
                :label="device.name"
                :value="device.id" /></el-select></el-form-item
          ><el-form-item label="模拟指令"
            ><el-select v-model="ruleForm.commandType"
              ><el-option label="PING" value="PING" /><el-option
                label="DISPENSE"
                value="DISPENSE" /><el-option
                label="TARE"
                value="TARE" /></el-select
          ></el-form-item>
        </div>
        <el-form-item
          v-if="ruleForm.commandType === 'DISPENSE'"
          label="模拟投放量"
          ><el-input-number
            v-model="ruleForm.amount"
            :controls="false"
            style="width: 100%" /></el-form-item></template
      ><el-form-item label="冷却时间（秒）"
        ><el-input-number
          v-model="ruleForm.cooldownSeconds"
          :min="0"
          :max="86400"
          style="width: 100%" /></el-form-item></el-form
    ><template #footer
      ><el-button @click="ruleDialog = false">取消</el-button
      ><el-button type="primary" @click="saveRule"
        >创建规则</el-button
      ></template
    ></el-dialog
  >
</template>
