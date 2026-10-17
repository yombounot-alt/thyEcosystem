export type ThemePreference = "system" | "light" | "dark";
const STORAGE_KEY = "thy-admin-theme";

export function readTheme(): ThemePreference {
  try {
    const value = localStorage.getItem(STORAGE_KEY);
    return value === "light" || value === "dark" ? value : "system";
  } catch {
    return "system";
  }
}

/** Applique le thème : `data-theme` force clair/sombre, son absence suit le système (tokens.css). */
export function applyTheme(theme: ThemePreference): void {
  if (theme === "system") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.setAttribute("data-theme", theme);
  try {
    if (theme === "system") localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // Stockage indisponible (navigation privée) : le choix vaut pour cette visite seulement.
  }
}
