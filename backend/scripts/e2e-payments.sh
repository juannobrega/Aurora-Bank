#!/bin/bash
API=http://localhost:8080
ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; echo "     $2"; }

# conta + rosto + login
U=$(curl -s -X POST $API/v1/onboarding/signup -H 'Content-Type: application/json' -d '{
  "fullName":"Juan Pablo","cpf":"529.982.247-25","email":"j@a.test","pin":"2846"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
F=$(python3 -c "
import random; random.seed(7)
print('['+','.join('%.6f'%random.random() for _ in range(128))+']')")
curl -s -X POST $API/v1/onboarding/face -H 'Content-Type: application/json' \
  -d "{\"userId\":\"$U\",\"features\":$F,\"algorithm\":\"aurora-face-v1\",\"quality\":0.9,\"livenessPassed\":true}" >/dev/null
T=$(curl -s -X POST $API/v1/auth/login/pin -H 'Content-Type: application/json' -d '{
  "cpf":"52998224725","pin":"2846","device":{"hardwareId":"h1","name":"iPhone"}}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['accessToken'])")
A="Authorization: Bearer $T"
curl -s -X POST $API/v1/credit/loans -H "$A" -H 'Content-Type: application/json' -d '{"amountCents":300000,"months":6}' >/dev/null

# linha digitável válida
LINE=$(python3 -c "
def m10(b):
    s=0;w=2
    for ch in reversed(b):
        p=int(ch)*w; s+= p-9 if p>9 else p; w=1 if w==2 else 2
    return (10-(s%10))%10
from datetime import date
f=(date(2026,12,1)-date(2025,2,22)).days+1000
free='0'*25; c1='3419'+free[:5]; c2=free[5:15]; c3=free[15:25]
print(c1+str(m10(c1))+c2+str(m10(c2))+c3+str(m10(c3))+'1'+'%04d%010d'%(f,18740))")

echo '=== Boleto: ler a linha digitável ==='
INSP=$(curl -s -X POST $API/v1/payments/boleto/inspect -H "$A" -H 'Content-Type: application/json' -d "{\"digitableLine\":\"$LINE\"}")
echo "$INSP" | grep -q '"payee":"Itaú Unibanco"' && ok "decodificou: $(echo "$INSP" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['payee'],d['amountCents'],'centavos, vence',d['dueDate'])")" || fail "inspect" "$INSP"

echo '=== Linha com DV errado deve ser recusada ==='
BAD="${LINE:0:9}$(( (${LINE:9:1} + 1) % 10 ))${LINE:10}"
R=$(curl -s -X POST $API/v1/payments/boleto/inspect -H "$A" -H 'Content-Type: application/json' -d "{\"digitableLine\":\"$BAD\"}")
echo "$R" | grep -q BOLETO_INVALIDO && ok "DV errado recusado" || fail "DV errado passou" "$R"

echo '=== Pagar boleto ==='
P=$(curl -s -X POST $API/v1/payments/boleto/pay -H "$A" -H 'Content-Type: application/json' -d "{\"digitableLine\":\"$LINE\"}")
echo "$P" | grep -q authCode && ok "boleto pago" || fail "pagamento" "$P"

echo '=== Pagar o mesmo boleto de novo deve ser recusado ==='
P2=$(curl -s -X POST $API/v1/payments/boleto/pay -H "$A" -H 'Content-Type: application/json' -d "{\"digitableLine\":\"$LINE\"}")
echo "$P2" | grep -q BOLETO_JA_PAGO && ok "pagamento duplicado barrado" || fail "pagou duas vezes!" "$P2"

echo '=== Recarga: identificar operadora ==='
Q=$(curl -s -X POST $API/v1/payments/recharge/quote -H "$A" -H 'Content-Type: application/json' -d '{"phone":"(11) 98873-3120"}')
echo "$Q" | grep -q Claro && ok "operadora: $(echo "$Q" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['carrier'],d['phone'])")" || fail "quote" "$Q"

echo '=== Recarregar ==='
RC=$(curl -s -X POST $API/v1/payments/recharge -H "$A" -H 'Content-Type: application/json' -d '{"phone":"11988733120","amountCents":2000}')
echo "$RC" | grep -q authCode && ok "recarga de R\$ 20,00 feita" || fail "recarga" "$RC"

echo '=== Valor de recarga fora da tabela deve ser recusado ==='
RB=$(curl -s -X POST $API/v1/payments/recharge -H "$A" -H 'Content-Type: application/json' -d '{"phone":"11988733120","amountCents":1735}')
echo "$RB" | grep -q VALOR_RECARGA_INVALIDO && ok "valor inválido recusado" || fail "aceitou valor fora da tabela" "$RB"

echo '=== Número inválido deve ser recusado ==='
RN=$(curl -s -X POST $API/v1/payments/recharge/quote -H "$A" -H 'Content-Type: application/json' -d '{"phone":"1188"}')
echo "$RN" | grep -q TELEFONE_INVALIDO && ok "número inválido recusado" || fail "aceitou número inválido" "$RN"
