import { fn } from "@ember/helper";
import AdminConfigAreaEmptyList from "discourse/admin/components/admin-config-area-empty-list";
import DBreadcrumbsItem from "discourse/ui-kit/d-breadcrumbs-item";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import { i18n } from "discourse-i18n";
import EharchiverTaskRow from "discourse/plugins/discourse-eharchiver/discourse/components/eharchiver-task-row";

export default <template>
  <DBreadcrumbsItem
    @path="/admin/plugins/discourse-eharchiver/tasks"
    @label={{i18n "admin.eharchiver.dashboard.title"}}
  />

  <section class="admin-detail eharchiver-task-dashboard">
    <DPageSubheader
      @titleLabel={{i18n "admin.eharchiver.dashboard.title"}}
      @descriptionLabel={{i18n "admin.eharchiver.dashboard.description"}}
    >
      <:actions>
        <DButton
          @action={{@controller.refresh}}
          @isLoading={{@controller.refreshing}}
          @icon="arrows-rotate"
          @label="admin.eharchiver.dashboard.refresh"
          class="btn-default"
        />
      </:actions>
    </DPageSubheader>

    {{#unless @model.meta.plugin_enabled}}
      <div class="alert alert-warning">
        {{i18n "admin.eharchiver.dashboard.plugin_disabled"}}
      </div>
    {{/unless}}

    <div
      class="eharchiver-task-dashboard__filters"
      role="group"
      aria-label={{i18n "admin.eharchiver.dashboard.filter_label"}}
    >
      {{#each @controller.filters as |filter|}}
        <DButton
          @action={{fn @controller.setFilter filter.value}}
          @translatedLabel={{filter.label}}
          class="btn-small {{if filter.active 'btn-primary' 'btn-default'}}"
        />
      {{/each}}
    </div>

    {{#if @controller.tasks.length}}
      <div class="eharchiver-task-dashboard__table-wrapper">
        <table class="d-table eharchiver-task-dashboard__table">
          <thead class="d-table__header">
            <tr class="d-table__row">
              <th class="d-table__cell">
                {{i18n "admin.eharchiver.dashboard.columns.source"}}
              </th>
              <th class="d-table__cell">
                {{i18n "admin.eharchiver.dashboard.columns.status"}}
              </th>
              <th class="d-table__cell">
                {{i18n "admin.eharchiver.dashboard.columns.quality"}}
              </th>
              <th class="d-table__cell">
                {{i18n "admin.eharchiver.dashboard.columns.created_at"}}
              </th>
              <th class="d-table__cell">
                {{i18n "admin.eharchiver.dashboard.columns.actions"}}
              </th>
            </tr>
          </thead>
          <tbody class="d-table__body">
            {{#each @controller.tasks as |task|}}
              <EharchiverTaskRow
                @task={{task}}
                @pluginEnabled={{@model.meta.plugin_enabled}}
                @retryingTaskId={{@controller.retryingTaskId}}
                @onRetry={{@controller.retry}}
              />
            {{/each}}
          </tbody>
        </table>
      </div>

      <nav
        class="eharchiver-task-dashboard__pagination"
        aria-label={{i18n "admin.eharchiver.dashboard.pagination"}}
      >
        <DButton
          @action={{@controller.previousPage}}
          @disabled={{@controller.previousPageDisabled}}
          @icon="chevron-left"
          @label="admin.eharchiver.dashboard.previous"
          class="btn-default btn-small"
        />
        <span>
          {{i18n
            "admin.eharchiver.dashboard.page"
            page=@controller.currentPage
          }}
        </span>
        <DButton
          @action={{@controller.nextPage}}
          @disabled={{@controller.nextPageDisabled}}
          @icon="chevron-right"
          @label="admin.eharchiver.dashboard.next"
          class="btn-default btn-small"
        />
      </nav>
    {{else}}
      <AdminConfigAreaEmptyList
        @emptyLabel="admin.eharchiver.dashboard.empty"
      />
    {{/if}}
  </section>
</template>
