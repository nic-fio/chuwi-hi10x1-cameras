import sys
n = sys.argv[1]
N = n.upper()
p = f"drivers/media/i2c/{n}.c"
s = open(p).read()
def rep(old, new):
    global s
    assert s.count(old) == 1, (old, s.count(old))
    s = s.replace(old, new)

# 1. niente cur_mode: l'altezza viene dallo stato attivo, il modo dal formato
rep(f"\tconst struct {n}_mode *cur_mode;\n", "")
rep(f"\t{n}->cur_mode = mode;\n\n", "")
rep(f"\t\tcontainer_of(ctrl->handler, struct {n}, ctrls);\n\ts64 exposure_max;\n\tint ret = 0;\n\n",
    f"\t\tcontainer_of(ctrl->handler, struct {n}, ctrls);\n"
    "\tconst struct v4l2_mbus_framefmt *format;\n"
    "\tstruct v4l2_subdev_state *state;\n"
    "\ts64 exposure_max;\n\tint ret = 0;\n\n"
    f"\tstate = v4l2_subdev_get_locked_active_state(&{n}->sd);\n"
    "\tformat = v4l2_subdev_state_get_format(state, 0);\n\n")
assert s.count(f"{n}->cur_mode->height") == 2
s = s.replace(f"{n}->cur_mode->height", "format->height")
rep(f"\tconst struct {n}_reg_list *reg_list;\n\tint ret;\n\n\tret = pm_runtime_resume_and_get({n}->dev);",
    f"\tconst struct v4l2_mbus_framefmt *format;\n"
    f"\tconst struct {n}_reg_list *reg_list;\n"
    f"\tconst struct {n}_mode *mode;\n\tint ret;\n\n"
    f"\tret = pm_runtime_resume_and_get({n}->dev);")
rep(f"\treg_list = &{n}->cur_mode->reg_list;\n",
    "\tformat = v4l2_subdev_state_get_format(state, 0);\n"
    f"\tmode = v4l2_find_nearest_size({n}_modes, ARRAY_SIZE({n}_modes),\n"
    "\t\t\t\t      width, height, format->width,\n"
    "\t\t\t\t      format->height);\n"
    "\treg_list = &mode->reg_list;\n")
rep(f"\t{n}->cur_mode = &{n}_modes[0];\n\n", "")

# 2. pm_runtime_get_if_active(): diverso da zero vuol dire anche "runtime PM
#    disabilitato", e allora si puo' accedere (camera-sensor.rst)
rep("\t/*\n\t * Not just != 0: the call returns -EINVAL when runtime PM is disabled,\n"
    "\t * and taking that for success would touch a powered down sensor and\n"
    "\t * then drop a reference that was never taken.\n\t */\n"
    f"\tif (pm_runtime_get_if_active({n}->dev) <= 0)\n",
    f"\tif (!pm_runtime_get_if_active({n}->dev))\n")

# 3. disable_streams: lo stream si ferma comunque, l'errore va solo nel log
rep(f"\tstruct {n} *{n} = to_{n}(sd);\n\tint ret;\n\n"
    f"\tret = cci_write({n}->regmap, {N}_REG_STREAM,\n"
    f"\t\t\t{N}_STREAM_OFF, NULL);\n\n"
    f"\tpm_runtime_put_autosuspend({n}->dev);\n\n\treturn ret;\n",
    f"\tstruct {n} *{n} = to_{n}(sd);\n\tint ret;\n\n"
    f"\tret = cci_write({n}->regmap, {N}_REG_STREAM,\n"
    f"\t\t\t{N}_STREAM_OFF, NULL);\n"
    "\tif (ret)\n"
    f"\t\tdev_err({n}->dev, \"failed to stop streaming: %d\\n\", ret);\n\n"
    f"\tpm_runtime_put_autosuspend({n}->dev);\n\n\treturn 0;\n")

# 4. clock senza nome: il firmware non ne definisce uno
rep(f"devm_v4l2_sensor_clk_get(dev, \"clk\")", "devm_v4l2_sensor_clk_get(dev, NULL)")
open(p, "w").write(s)
