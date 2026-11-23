CREATE DATABASE IF NOT EXISTS sistema_os_altave
DEFAULT CHARACTER SET utf8mb4
DEFAULT COLLATE utf8mb4_unicode_ci;

USE sistema_os_altave;

-- 1. Tabela PAPEL
CREATE TABLE PAPEL (
    id_papel INT AUTO_INCREMENT PRIMARY KEY,
    nome_papel VARCHAR(50) NOT NULL,
    descricao VARCHAR(255)
) ENGINE=InnoDB;

-- 2. Tabela TIME
CREATE TABLE `TIME` (
    id_time INT AUTO_INCREMENT PRIMARY KEY,
    nome_time VARCHAR(50) NOT NULL,
    descricao VARCHAR(255)
) ENGINE=InnoDB;

-- 3. Tabela USUARIO
CREATE TABLE USUARIO (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    senha VARCHAR(255) NOT NULL,
    data_cadastro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_time INT NOT NULL,
    id_papel INT NOT NULL,
    CONSTRAINT fk_usuario_time FOREIGN KEY (id_time) REFERENCES `TIME`(id_time),
    CONSTRAINT fk_usuario_papel FOREIGN KEY (id_papel) REFERENCES PAPEL(id_papel)
) ENGINE=InnoDB;

-- 4. Tabela ORDEM_SERVICO
CREATE TABLE ORDEM_SERVICO (
    id_os INT AUTO_INCREMENT PRIMARY KEY,
    tipo VARCHAR(20) NOT NULL,
    titulo VARCHAR(150) NOT NULL,
    descricao TEXT NOT NULL,
    status VARCHAR(30) NOT NULL,
    prioridade VARCHAR(20) NOT NULL,
    data_abertura DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    prazo DATE,
    id_solicitante INT NOT NULL,
    id_time_responsavel INT NOT NULL,
    id_usuario_responsavel INT NULL,
    CONSTRAINT fk_os_solicitante FOREIGN KEY (id_solicitante) REFERENCES USUARIO(id_usuario),
    CONSTRAINT fk_os_time_responsavel FOREIGN KEY (id_time_responsavel) REFERENCES `TIME`(id_time),
    CONSTRAINT fk_os_usuario_responsavel FOREIGN KEY (id_usuario_responsavel) REFERENCES USUARIO(id_usuario)
) ENGINE=InnoDB;

-- 5. Tabela HISTORICO_OS
CREATE TABLE HISTORICO_OS (
    id_historico INT AUTO_INCREMENT PRIMARY KEY,
    id_os INT NOT NULL,
    id_usuario INT NOT NULL,
    data_hora DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    acao VARCHAR(50) NOT NULL,
    descricao TEXT,
    CONSTRAINT fk_historico_os FOREIGN KEY (id_os) REFERENCES ORDEM_SERVICO(id_os) ON DELETE CASCADE,
    CONSTRAINT fk_historico_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIO(id_usuario)
) ENGINE=InnoDB;

-- 6. Tabela ANEXO
CREATE TABLE ANEXO (
    id_anexo INT AUTO_INCREMENT PRIMARY KEY,
    id_os INT NOT NULL,
    id_usuario INT NOT NULL,
    nome_arquivo VARCHAR(150) NOT NULL,
    caminho VARCHAR(255) NOT NULL,
    data_upload DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_anexo_os FOREIGN KEY (id_os) REFERENCES ORDEM_SERVICO(id_os) ON DELETE CASCADE,
    CONSTRAINT fk_anexo_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIO(id_usuario)
) ENGINE=InnoDB;

-- 7. Tabela NOTIFICACAO
CREATE TABLE NOTIFICACAO (
    id_notificacao INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_os INT NOT NULL,
    mensagem VARCHAR(255) NOT NULL,
    lida BOOLEAN NOT NULL DEFAULT FALSE,
    data_envio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_notificacao_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIO(id_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_notificacao_os FOREIGN KEY (id_os) REFERENCES ORDEM_SERVICO(id_os) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 8. Tabela VERIFICACAO_QUALIDADE
CREATE TABLE VERIFICACAO_QUALIDADE (
    id_verificacao INT AUTO_INCREMENT PRIMARY KEY,
    id_os INT NOT NULL,
    id_usuario INT NOT NULL,
    resultado VARCHAR(20) NOT NULL,
    observacoes TEXT,
    data_verificacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_verificacao_os FOREIGN KEY (id_os) REFERENCES ORDEM_SERVICO(id_os) ON DELETE CASCADE,
    CONSTRAINT fk_verificacao_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIO(id_usuario)
) ENGINE=InnoDB;
