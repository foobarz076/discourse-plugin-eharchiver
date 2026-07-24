import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-eharchiver";

export default {
  name: "eharchiver-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "box-archive");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "admin.eharchiver.dashboard.title",
          route: "adminPlugins.show.discourse-eharchiver-tasks",
          description: "admin.eharchiver.dashboard.description",
        },
      ]);
    });
  },
};
