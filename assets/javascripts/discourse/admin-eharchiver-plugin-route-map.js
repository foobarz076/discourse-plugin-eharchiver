export default {
  resource: "admin.adminPlugins.show",

  path: "/plugins",

  map() {
    this.route("discourse-eharchiver-tasks", { path: "tasks" });
  },
};
