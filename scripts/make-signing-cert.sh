#!/bin/zsh
# 生成一个本机自签名代码签名证书「OneSync Local Signing」，放在独立钥匙串 ~/.onesync-signing。
# 用固定证书签名后，App 的签名身份不随重新编译变化，钥匙串里保存的密码不会失效。
# 只在本机使用，证书和私钥不离开这台 Mac。
set -e
S=~/.onesync-signing
[ -f $S/signing.keychain-db ] && { echo "已存在：$S"; exit 0; }
mkdir -p $S && chmod 700 $S && cd $S
cat > c.cnf <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=OneSync Local Signing
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 3650 -config c.cnf 2>/dev/null
P=$(openssl rand -hex 12)
openssl pkcs12 -export -inkey k.pem -in c.pem -out c.p12 -passout pass:$P 2>/dev/null
KP=$(openssl rand -hex 16); print -n $KP > kc.pass; chmod 600 kc.pass
security create-keychain -p $KP $S/signing.keychain-db
security set-keychain-settings $S/signing.keychain-db
security unlock-keychain -p $KP $S/signing.keychain-db
security import c.p12 -k $S/signing.keychain-db -P $P -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k $KP $S/signing.keychain-db >/dev/null
rm -f k.pem c.p12
# 加进用户钥匙串搜索列表，codesign 才找得到
security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') $S/signing.keychain-db
echo "完成：OneSync Local Signing"
