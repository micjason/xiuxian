import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router";
import { getToken } from "./api";
import AdminLayout from "./layouts/AdminLayout.vue";
import { legacyRedirects } from "./nav";
import LoginView from "./views/LoginView.vue";

const redirects: RouteRecordRaw[] = Object.entries(legacyRedirects).map(([from, to]) => ({ path: from, redirect: to }));

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: "/login", component: LoginView },
    {
      path: "/",
      component: AdminLayout,
      children: [
        { path: "", redirect: "/dashboard" },
        { path: "dashboard", component: () => import("./views/dashboard/DashboardView.vue") },
        { path: "players", component: () => import("./views/players/PlayersView.vue") },
        { path: "config/overview", component: () => import("./views/config/ConfigOverviewView.vue") },
        { path: "config/gear", component: () => import("./views/config/GearView.vue") },
        { path: "config/realms", component: () => import("./views/config/RealmsView.vue") },
        { path: "config/items", component: () => import("./views/config/ItemsView.vue") },
        { path: "config/skills", component: () => import("./views/config/SkillsView.vue") },
        { path: "config/chapters", component: () => import("./views/config/ChaptersView.vue") },
        { path: "config/stages", component: () => import("./views/config/StagesView.vue") },
        { path: "config/enhance", component: () => import("./views/config/EnhanceView.vue") },
        { path: "config/dongfu", component: () => import("./views/config/DongfuView.vue") },
        { path: "config/combat", component: () => import("./views/config/CombatView.vue") },
        { path: "publish", component: () => import("./views/publish/PublishView.vue") },
        { path: "publish/versions", component: () => import("./views/publish/VersionsView.vue") },
        { path: "publish/client", component: () => import("./views/publish/ClientView.vue") },
        { path: "ops/announcements", component: () => import("./views/ops/AnnouncementsView.vue") },
        { path: "ops/popups", component: () => import("./views/ops/PopupsView.vue") },
        { path: "system/admins", component: () => import("./views/system/AdminsView.vue") },
        { path: "system/audit", component: () => import("./views/system/AuditView.vue") },
        { path: "system/settings", component: () => import("./views/system/SettingsView.vue") },
        ...redirects,
        { path: ":pathMatch(.*)*", redirect: "/dashboard" },
      ],
    },
  ],
});

router.beforeEach((to) => {
  if (to.path !== "/login" && !getToken()) {
    return "/login";
  }
  if (to.path === "/login" && getToken()) {
    return "/dashboard";
  }
  return true;
});
