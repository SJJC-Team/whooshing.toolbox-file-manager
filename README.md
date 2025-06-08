# Whooshing 文件系统

本项目为 [Whooshing](https://github.com/SJJC-Team/whooshing) 系统的**文件系统依赖库**，旨在构建一套流式、强安全、隐私保护的文件传输与存储加密系统。契合 [Whooshing](https://github.com/SJJC-Team/whooshing) 系统，强调模块之间的数据不透明性、文件系统可扩展性，以及对用户数据的零信任加密。



### 特性

- **数据块流式加密**：支持文件分块加密与传输，每一块数据独立加密，增强抗流量分析能力。
- **目录层级隐藏**：使用扁平化索引系统，隐藏真实目录结构，保护文件组织结构隐私。
- **密钥不唯一性**：每个文件派生独立密钥，保障密钥非复用，即使攻击者获取密钥数据库，也无法解密其他文件。
- **服务透明性**：对服务器模块透明，服务端无法读取任何用户数据，仅作为加密数据中转通道。
- **基于模块的密钥获取认证**：服务模块不记录用户密钥，必须通过认证模块授权获取。

----------

### 流程介绍

系统由客户端、服务器、认证模块组成，采用分模块通信和 Whooshing 加密隧道。

1. 客户端从本地读取文件并按块加密。
2. 每块加密数据通过 Whooshing 加密隧道发送至服务端。
3. 服务端临时缓存数据块，供后续文件系统写入使用。
4. 文件元信息与加密参数写入索引数据库。

传输过程中 **TLS 加密**（HTTP）或 **Whooshing 加密隧道**（API、INLINE）确保数据通道安全。



#### 加密机制

![系统流程](diagrams/2.系统流程.png)

#### 索引数据库

![索引数据库](diagrams/3.索引数据库.png)

-------

### 联系与反馈

如有使用问题或建议，请通过 [GitHub Issues](https://github.com/SJJC-Team/whooshing.toolbox-file-system/issues) 提交反馈。

或发至邮箱 [contact@official.whooshings.space](mailto:contact@official.whooshings.space)
