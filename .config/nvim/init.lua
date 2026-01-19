require("config.lazy")

-- Set Bash as the shell, pulled from the top of PATH
vim.o.shell = vim.fn.exepath("bash")

if vim.fn.executable("pyenv") == 1 then
  local pyenv_home = vim.fn.system("pyenv root"):gsub("\n", "")
  -- Find the latest python3 among all pyenv virtualenvs that start with "nvim-"
  local nvim_versions = vim.fn.systemlist("pyenv versions --bare")
  local latest_nvim_venv = ""
  for _, version in ipairs(nvim_versions) do
    if version:match("^nvim%-") then
      if latest_nvim_venv == "" or version > latest_nvim_venv then
        latest_nvim_venv = version
      end
    end
  end
  -- Set the python3 host program to the latest nvim virtualenv
  if latest_nvim_venv == "" then
    local latest_pyenv_version = vim.fn.system("pyenv latest --known 3"):gsub("\n", "")
    vim.fn.system("pyenv install " .. latest_pyenv_version)
    vim.fn.system("pyenv virtualenv " .. latest_pyenv_version .. " nvim-" .. latest_pyenv_version)

    vim.g.python3_host_prog = pyenv_home .. "/versions/nvim-" .. latest_pyenv_version .. "/bin/python"
  else
    vim.g.python3_host_prog = pyenv_home .. "/versions/" .. latest_nvim_venv .. "/bin/python"
  end
end
