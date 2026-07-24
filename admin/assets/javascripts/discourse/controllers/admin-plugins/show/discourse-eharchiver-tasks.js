import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { cancel, later } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const ROUTE_NAME = "adminPlugins.show.discourse-eharchiver-tasks";
const REFRESH_INTERVAL_MS = 10_000;

export default class AdminPluginsShowDiscourseEharchiverTasksController extends Controller {
  @service router;
  @service toasts;

  @tracked refreshing = false;
@tracked retryingTaskId = null;
queryParams = ["status", "page"];

  status = "all";
  page = 0;

  
  

  pollTimer = null;

  get tasks() {
    return this.model.tasks;
  }

  get filters() {
    return ["all", "active", "failed", "completed"].map((value) => ({
      value,
      active: this.status === value,
      label: i18n(`admin.eharchiver.dashboard.filters.${value}`),
    }));
  }

  get currentPage() {
    return Number(this.page) + 1;
  }

  get hasPreviousPage() {
    return Number(this.page) > 0;
  }

  get hasNextPage() {
    return this.model.meta.has_more;
  }

  get previousPageDisabled() {
    return !this.hasPreviousPage;
  }

  get nextPageDisabled() {
    return !this.hasNextPage;
  }

  startPolling() {
    this.stopPolling();
    this.pollTimer = later(this, this.refresh, REFRESH_INTERVAL_MS);
  }

  stopPolling() {
    if (this.pollTimer) {
      cancel(this.pollTimer);
      this.pollTimer = null;
    }
  }

  @action
  setFilter(status) {
    this.router.transitionTo(ROUTE_NAME, {
      queryParams: { status, page: 0 },
    });
  }

  @action
  previousPage() {
    this.router.transitionTo(ROUTE_NAME, {
      queryParams: {
        status: this.status,
        page: Math.max(Number(this.page) - 1, 0),
      },
    });
  }

  @action
  nextPage() {
    this.router.transitionTo(ROUTE_NAME, {
      queryParams: {
        status: this.status,
        page: Number(this.page) + 1,
      },
    });
  }

  @action
  async refresh() {
    this.stopPolling();
    this.refreshing = true;

    try {
      await this.router.refresh(ROUTE_NAME);
    } catch (error) {
      popupAjaxError(error);
      this.startPolling();
    } finally {
      this.refreshing = false;
    }
  }

  @action
  async retry(task) {
    this.retryingTaskId = task.task_id;

    try {
      await ajax(`/eharchiver/admin/tasks/${task.task_id}/retry.json`, {
        type: "POST",
      });
      this.toasts.success({
        duration: "short",
        data: {
          message: i18n("admin.eharchiver.dashboard.retry_started"),
        },
      });
      await this.router.refresh(ROUTE_NAME);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.retryingTaskId = null;
    }
  }
}
