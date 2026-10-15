<template>
  <div>
    <PageHeader title="公告" desc="玩家登录后弹出的公告。公告接口暂不支持删除，下线请关闭「启用」。" />
    <ConfigListPage
      :schema="announcementSchema"
      :rows="rows"
      :loading="loading"
      :error="error"
      id-key="id"
      entity-name="公告"
      :search-keys="['title', 'body']"
      :hidden-keys="['id']"
      :filters="[{ key: 'enabled', label: '状态', options: [{ label: '已启用', value: 'true' }, { label: '未启用', value: 'false' }] }]"
      creatable
      :new-row="() => ({ ...defaultsOf(announcementSchema) })"
      :save-fn="save"
      :refresh-draft="false"
      saved-message="已保存，玩家下次登录可见"
      export-name="公告"
      @reload="reload"
    />
  </div>
</template>

<script setup lang="ts">
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import PageHeader from "../../components/PageHeader.vue";
import { useList } from "../../composables/useList";
import { announcementSchema } from "../../schema/resources";
import { defaultsOf } from "../../schema/validate";

const { rows, loading, error, reload } = useList(() => api<Record<string, unknown>[]>("/admin/announcements"));

async function save(values: Record<string, unknown>): Promise<void> {
  await api("/admin/announcements", {
    method: "POST",
    body: JSON.stringify({ id: values.id || undefined, title: values.title, body: values.body, enabled: values.enabled }),
  });
}
</script>
