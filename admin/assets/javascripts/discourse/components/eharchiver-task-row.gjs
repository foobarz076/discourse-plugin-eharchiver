import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";

export default class EharchiverTaskRow extends Component {
  get stageLabel() {
    return i18n(`admin.eharchiver.dashboard.stages.${this.args.task.stage}`);
  }

  get qualityLabel() {
    return i18n(
      `admin.eharchiver.dashboard.qualities.${this.args.task.quality}`
    );
  }

  get retryDisabled() {
    return !this.args.pluginEnabled;
  }

  <template>
    <tr class="d-table__row eharchiver-task-dashboard__row">
      <td class="d-table__cell --overview">
        <div class="eharchiver-task-dashboard__source">
          <a href={{@task.source_url}}>
            {{@task.topic.title}}
          </a>
        </div>
        <div class="eharchiver-task-dashboard__meta">
          <span>
            {{i18n
              "admin.eharchiver.dashboard.requested_by"
              username=@task.user.username
            }}
          </span>
          <a
            href={{@task.gallery_url}}
            target="_blank"
            rel="noopener noreferrer"
          >
            {{i18n "admin.eharchiver.dashboard.gallery"}}
          </a>
          {{#if @task.retried_from_task_id}}
            <span>{{i18n "admin.eharchiver.dashboard.retry_attempt"}}</span>
          {{/if}}
        </div>
        {{#if @task.error_message}}
          <div class="eharchiver-task-dashboard__error" role="alert">
            {{@task.error_message}}
          </div>
        {{/if}}
      </td>
      <td class="d-table__cell">
        <span
          class="eharchiver-task-dashboard__status eharchiver-task-dashboard__status--{{@task.stage}}"
        >
          {{this.stageLabel}}
        </span>
      </td>
      <td class="d-table__cell">
        {{this.qualityLabel}}
      </td>
      <td class="d-table__cell">
        {{dFormatDate @task.created_at}}
      </td>
      <td class="d-table__cell --controls">
        <div class="d-table__cell-actions">
          {{#if @task.result_url}}
            <a
              class="btn btn-default btn-small"
              href={{@task.result_url}}
              title={{i18n "admin.eharchiver.dashboard.view_result"}}
            >
              {{i18n "admin.eharchiver.dashboard.view_result"}}
            </a>
          {{/if}}
          {{#if @task.retryable}}
            <DButton
              @action={{fn @onRetry @task}}
              @disabled={{this.retryDisabled}}
              @isLoading={{eq @retryingTaskId @task.task_id}}
              @icon="rotate-right"
              @label="admin.eharchiver.dashboard.retry"
              @title="admin.eharchiver.dashboard.retry"
              class="btn-primary btn-small"
            />
          {{/if}}
        </div>
      </td>
    </tr>
  </template>
}
