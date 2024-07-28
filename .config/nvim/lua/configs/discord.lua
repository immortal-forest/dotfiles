require("neocord").setup {
  -- General options
  logo = "auto",
  logo_tooltip = "i use arch btw",
  main_image = "language",
  log_level = nil,
  debounce_timeout = 10,
  show_time = true, -- Show the timer
  global_timer = true, -- if set true, timer won't update when any event are triggered

  -- Rich Presence text options
  editing_text = "Editing %s",
  file_explorer_text = "Browsing %s",
  git_commit_text = "Committing changes",
  plugin_manager_text = "Managing plugins",
  reading_text = "Reading %s",
  workspace_text = "Working on %s",
  line_number_text = "Line %s out of %s",
  terminal_text = "Using Terminal",
}
