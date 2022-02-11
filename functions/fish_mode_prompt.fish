function fish_mode_prompt
  switch $fish_bind_mode
    case default
      echo 'n'
    case insert
      echo 'i'
    case replace_one
      echo 'r'
    case visual
      echo 'v'
    case '*'
      echo '?'
  end
end
