import { useEffect } from "react";
import { useRoute } from "./router";
import { store } from "./store";
import { TabBar, Wallpaper } from "./ui";
import { AppearanceScreen } from "./screens/AppearanceScreen";
import { ConnectScreen } from "./screens/ConnectScreen";
import { HistoryScreen } from "./screens/HistoryScreen";
import { LightsScreen } from "./screens/LightsScreen";
import { PresetEditScreen } from "./screens/PresetEditScreen";
import { PresetsScreen } from "./screens/PresetsScreen";
import { SessionScreen } from "./screens/SessionScreen";

export function App() {
  const route = useRoute();

  useEffect(() => {
    void store.reconnectRemembered();
  }, []);

  let screen;
  switch (route.name) {
    case "presets": screen = <PresetsScreen />; break;
    case "preset": screen = <PresetEditScreen index={route.index} />; break;
    case "lights": screen = <LightsScreen />; break;
    case "history": screen = <HistoryScreen />; break;
    case "appearance": screen = <AppearanceScreen />; break;
    case "connect": screen = <ConnectScreen />; break;
    default: screen = <SessionScreen />;
  }

  return (
    <>
      <Wallpaper />
      {screen}
      <TabBar />
    </>
  );
}
