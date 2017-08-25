Eru load balance
================

ELB(Eru load balance)是基于 [openresty](https://openresty.org/en/) 开发的 load balancer，在 eru 体系中，它负责将流量分发到各个容器中，ELB 的优点在于它允许灵活复杂的分流条件。

Features
========

* 动态更新后端容器路由
* 0 down 机切换流量（基于 [ngx_http_dyups_module](https://github.com/yzprofile/ngx_http_dyups_module)）
* 自定义流量分发策略
* 本身作为 Eru app 可以被 Eru 进行管理
* 本身也提供了 Python 3 的 client binding

One more thing
==============

为了在 LB 层面知道是出问题的时候是哪个 LB，因此我们对 nginx 做了一小点修改，通过 ERU_INFO 的环境变量传入 custom_token 来甄别是哪台 LB。
