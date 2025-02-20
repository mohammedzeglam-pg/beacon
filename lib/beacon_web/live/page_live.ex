defmodule BeaconWeb.PageLive do
  use BeaconWeb, :live_view
  use Phoenix.HTML
  require Logger
  import Phoenix.Component

  def mount(:not_mounted_at_router, _params, socket) do
    {:ok, socket}
  end

  def mount(params, session, socket) do
    %{"path" => path} = params
    %{"beacon_site" => site} = session

    socket =
      socket
      |> assign(:beacon, %{site: site})
      |> assign(:__site__, site)

    if connected?(socket), do: :ok = Beacon.PubSub.subscribe_page_update(site, path)

    {:ok, socket, layout: {BeaconWeb.Layouts, :dynamic}}
  end

  def render(assigns) do
    {{site, path}, {_page_id, _layout_id, format, template, _page_module, _component_module}} = lookup_route!(assigns.__site__, assigns.__live_path__)
    Beacon.Lifecycle.render_template(site: site, path: path, format: format, template: template, assigns: assigns, env: __ENV__)
  end

  defp lookup_route!(site, path) do
    Beacon.Router.lookup_path(site, path) ||
      raise BeaconWeb.NotFoundError, """
      Route not found for path #{inspect(path)}

      Make sure a page was created for that path.
      """
  end

  def handle_info(:page_updated, socket) do
    # TODO: disable automatic template reload (repaint) in favor of https://github.com/BeaconCMS/beacon/issues/179
    %{assigns: %{__beacon_page_params__: params}} = socket

    socket =
      socket
      # |> assign(:__page_updated_at, DateTime.utc_now())
      # |> assign(:page_title, page_title(params, socket.assigns))
      |> push_event("beacon:page-updated", %{
        meta_tags: meta_tags(params, socket.assigns)
        # runtime_css_path: BeaconWeb.Layouts.asset_path(socket, :css)
      })

    {:noreply, socket}
  end

  def handle_event(event_name, event_params, socket) do
    socket.assigns.__beacon_page_module__
    |> Beacon.Loader.call_function_with_retry(
      :handle_event,
      [socket.assigns.__live_path__, event_name, event_params, socket]
    )
    |> case do
      {:noreply, %Phoenix.LiveView.Socket{} = socket} ->
        {:noreply, socket}

      other ->
        raise "handle_event for #{socket.assigns.__live_path__} expected return of {:noreply, %Phoenix.LiveView.Socket{}}, but got #{inspect(other)}"
    end
  end

  def handle_params(params, _url, socket) do
    %{"path" => path} = params
    %{__site__: site} = socket.assigns
    live_data = Beacon.DataSource.live_data(site, path, Map.drop(params, ["path"]))
    {{_site, _path}, {page_id, layout_id, _format, _template, page_module, component_module}} = lookup_route!(site, path)

    beacon_attrs = %Beacon.BeaconAttrs{site: site, prefix: socket.router.__beacon_site_prefix__(site)}
    Process.put(:__beacon_attrs__, beacon_attrs)

    socket =
      socket
      |> assign(:beacon, %{site: site})
      |> assign(:beacon_live_data, live_data)
      |> assign(:beacon_attrs, beacon_attrs)
      |> assign(:__live_path__, path)
      |> assign(:__page_updated_at, DateTime.utc_now())
      |> assign(:__dynamic_layout_id__, layout_id)
      |> assign(:__dynamic_page_id__, page_id)
      |> assign(:__site__, site)
      |> assign(:__beacon_page_module__, page_module)
      |> assign(:__beacon_component_module__, component_module)
      |> assign(:__beacon_page_params__, params)

    socket =
      socket
      |> assign(:page_title, page_title(params, socket.assigns))
      |> push_event("beacon:page-updated", %{meta_tags: meta_tags(params, socket.assigns)})

    {:noreply, socket}
  end

  defp page_title(params, %{__site__: site, __live_path__: path, beacon_live_data: live_data} = assigns) do
    Beacon.DataSource.page_title(site, path, params, live_data, BeaconWeb.Layouts.page_title(assigns))
  end

  defp meta_tags(params, %{__site__: site, __live_path__: path, beacon_live_data: live_data} = assigns) do
    Beacon.DataSource.meta_tags(site, path, params, live_data, BeaconWeb.Layouts.meta_tags(assigns))
  end
end
