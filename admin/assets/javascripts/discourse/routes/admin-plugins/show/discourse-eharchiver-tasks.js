import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class AdminPluginsShowDiscourseEharchiverTasksRoute extends DiscourseRoute {
  queryParams = {
    status: { refreshModel: true, replace: true },
    page: { refreshModel: true, replace: true },
  };

  async model(params) {
    return await ajax("/eharchiver/admin/tasks.json", {
      data: {
        status: params.status || "all",
        page: params.page || 0,
      },
    });
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.startPolling();
  }

  resetController(controller, isExiting) {
    super.resetController(...arguments);
    if (isExiting) {
      controller.stopPolling();
    }
  }

  titleToken() {
    return i18n("admin.eharchiver.dashboard.title");
  }
}
