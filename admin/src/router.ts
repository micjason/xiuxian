import { createRouter, createWebHistory } from "vue-router";
import { getToken } from "./api";
import AdminLayout from "./layouts/AdminLayout.vue";
import AnnouncementsView from "./views/AnnouncementsView.vue";
import BuildingsView from "./views/BuildingsView.vue";
import ItemsView from "./views/ItemsView.vue";
import LoginView from "./views/LoginView.vue";
import OperationsView from "./views/OperationsView.vue";
import PlayersView from "./views/PlayersView.vue";
import PuppetsView from "./views/PuppetsView.vue";
import PopupsView from "./views/PopupsView.vue";
import PublishView from "./views/PublishView.vue";
import RealmsView from "./views/RealmsView.vue";
import RulesView from "./views/RulesView.vue";
import ReleasesView from "./views/ReleasesView.vue";
import SkillsView from "./views/SkillsView.vue";
import StagesView from "./views/StagesView.vue";
import WeaponsView from "./views/WeaponsView.vue";

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: "/login", component: LoginView },
    {
      path: "/",
      component: AdminLayout,
      children: [
        { path: "", redirect: "/realms" },
        { path: "rules", component: RulesView },
        { path: "realms", component: RealmsView },
        { path: "skills", component: SkillsView },
        { path: "weapons", component: WeaponsView },
        { path: "items", component: ItemsView },
        { path: "stages", component: StagesView },
        { path: "puppets", component: PuppetsView },
        { path: "buildings", component: BuildingsView },
        { path: "publish", component: PublishView },
        { path: "releases", component: ReleasesView },
        { path: "announcements", component: AnnouncementsView },
        { path: "popups", component: PopupsView },
        { path: "players", component: PlayersView },
        { path: "operations", component: OperationsView },
      ],
    },
  ],
});

router.beforeEach((to) => {
  if (to.path !== "/login" && !getToken()) {
    return "/login";
  }
  if (to.path === "/login" && getToken()) {
    return "/realms";
  }
  return true;
});
