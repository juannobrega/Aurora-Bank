#!/bin/bash
API=http://localhost:8080
ok(){ echo "  ✅ $1"; }
fail(){ echo "  ❌ $1"; echo "     $2"; FAILED=1; }

echo "=== 1. Criar conta ==="
SIGNUP=$(curl -s -X POST $API/v1/onboarding/signup -H 'Content-Type: application/json' -d '{
  "fullName":"Juan Pablo Nobrega","cpf":"529.982.247-25",
  "email":"juan@aurora.test","phone":"11998887766","pin":"2846"}')
USER_ID=$(echo "$SIGNUP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
STATUS=$(echo "$SIGNUP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
[ -n "$USER_ID" ] && ok "conta criada, status=$STATUS" || fail "signup falhou" "$SIGNUP"

echo "=== 2. CPF duplicado deve ser recusado ==="
DUP=$(curl -s -X POST $API/v1/onboarding/signup -H 'Content-Type: application/json' -d '{
  "fullName":"Outra Pessoa","cpf":"529.982.247-25","email":"outro@aurora.test","pin":"9137"}')
echo "$DUP" | grep -q CPF_JA_CADASTRADO && ok "CPF duplicado recusado" || fail "duplicado passou" "$DUP"

echo "=== 3. Login antes do rosto deve exigir KYC ==="
EARLY=$(curl -s -X POST $API/v1/auth/login/pin -H 'Content-Type: application/json' -d "{
  \"cpf\":\"52998224725\",\"pin\":\"2846\",
  \"device\":{\"hardwareId\":\"iphone-juan-01\",\"name\":\"iPhone de Juan\"}}")
echo "$EARLY" | grep -q KYC_PENDENTE && ok "conta sem rosto não entra" || fail "entrou sem KYC" "$EARLY"

echo "=== 4. Cadastrar rosto (ativa a conta) ==="
FEATURES=$(python3 -c "
import random; random.seed(42)
print('[' + ','.join('%.6f'%random.random() for _ in range(128)) + ']')")
ENROLL=$(curl -s -X POST $API/v1/onboarding/face -H 'Content-Type: application/json' -d "{
  \"userId\":\"$USER_ID\",\"features\":$FEATURES,\"algorithm\":\"aurora-face-v1\",
  \"quality\":0.92,\"livenessPassed\":true}")
echo "$ENROLL" | grep -q ACTIVE && ok "rosto cadastrado, conta ACTIVE" || fail "enroll falhou" "$ENROLL"

echo "=== 5. Login com PIN ==="
LOGIN=$(curl -s -X POST $API/v1/auth/login/pin -H 'Content-Type: application/json' -d "{
  \"cpf\":\"52998224725\",\"pin\":\"2846\",
  \"device\":{\"hardwareId\":\"iphone-juan-01\",\"name\":\"iPhone de Juan\",\"model\":\"iPhone14,5\"}}")
TOKEN=$(echo "$LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin).get('accessToken',''))" 2>/dev/null)
REFRESH=$(echo "$LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin).get('refreshToken',''))" 2>/dev/null)
[ -n "$TOKEN" ] && ok "login por PIN" || fail "login falhou" "$LOGIN"
AUTH="Authorization: Bearer $TOKEN"

echo "=== 6. PIN errado deve ser recusado ==="
BAD=$(curl -s -X POST $API/v1/auth/login/pin -H 'Content-Type: application/json' -d "{
  \"cpf\":\"52998224725\",\"pin\":\"9999\",
  \"device\":{\"hardwareId\":\"iphone-juan-01\",\"name\":\"iPhone\"}}")
echo "$BAD" | grep -q PIN_INCORRETO && ok "PIN errado recusado" || fail "PIN errado passou" "$BAD"

echo "=== 7. Login com rosto ==="
FACE_LOGIN=$(curl -s -X POST $API/v1/auth/login/face -H 'Content-Type: application/json' -d "{
  \"cpf\":\"52998224725\",\"features\":$FEATURES,\"algorithm\":\"aurora-face-v1\",
  \"livenessPassed\":true,
  \"device\":{\"hardwareId\":\"iphone-juan-01\",\"name\":\"iPhone de Juan\"}}")
echo "$FACE_LOGIN" | grep -q accessToken && ok "login por rosto" || fail "login facial falhou" "$FACE_LOGIN"

echo "=== 8. Rosto de outra pessoa deve ser recusado ==="
OTHER=$(python3 -c "
import random; random.seed(999)
print('[' + ','.join('%.6f'%random.random() for _ in range(128)) + ']')")
IMPOSTOR=$(curl -s -X POST $API/v1/auth/login/face -H 'Content-Type: application/json' -d "{
  \"cpf\":\"52998224725\",\"features\":$OTHER,\"algorithm\":\"aurora-face-v1\",
  \"livenessPassed\":true,
  \"device\":{\"hardwareId\":\"iphone-juan-01\",\"name\":\"iPhone\"}}")
echo "$IMPOSTOR" | grep -q ROSTO_NAO_CONFERE && ok "impostor recusado" || fail "impostor entrou!" "$IMPOSTOR"

echo "=== 9. Foto sem prova de vida deve ser recusada ==="
NOLIVE=$(curl -s -X POST $API/v1/auth/login/face -H 'Content-Type: application/json' -d "{
  \"cpf\":\"52998224725\",\"features\":$FEATURES,\"algorithm\":\"aurora-face-v1\",
  \"livenessPassed\":false,
  \"device\":{\"hardwareId\":\"iphone-juan-01\",\"name\":\"iPhone\"}}")
echo "$NOLIVE" | grep -q PROVA_DE_VIDA && ok "foto sem prova de vida barrada" || fail "passou sem liveness" "$NOLIVE"

echo "=== 10. Snapshot da conta ==="
SNAP=$(curl -s "$API/v1/account/snapshot" -H "$AUTH")
echo "$SNAP" | grep -q balanceCents && ok "snapshot: saldo $(echo "$SNAP" | python3 -c "import json,sys; print(json.load(sys.stdin)['balanceCents'])")" || fail "snapshot falhou" "$SNAP"

echo "=== 11. Sem token deve ser 401 ==="
NOAUTH=$(curl -s -o /dev/null -w "%{http_code}" $API/v1/account/snapshot)
[ "$NOAUTH" = "401" ] && ok "rota protegida exige token" || fail "acesso sem token: HTTP $NOAUTH" ""

echo "=== 12. Contratar empréstimo (dinheiro entra + dívida) ==="
LOAN=$(curl -s -X POST $API/v1/credit/loans -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"amountCents":500000,"months":12}')
LOAN_ID=$(echo "$LOAN" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
[ -n "$LOAN_ID" ] && ok "empréstimo: devedor $(echo "$LOAN" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['outstandingCents'])") centavos em $(echo "$LOAN" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['schedule']))") parcelas" || fail "empréstimo falhou" "$LOAN"

BAL=$(curl -s $API/v1/account/balance -H "$AUTH" | python3 -c "import json,sys; print(json.load(sys.stdin)['amountCents'])")
[ "$BAL" = "500000" ] && ok "saldo creditado: R\$ 5.000,00" || fail "saldo inesperado: $BAL" ""

echo "=== 13. Enviar Pix ==="
PIX=$(curl -s -X POST $API/v1/pix/send -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"pixKey":"amigo@email.com","amountCents":6000,"note":"almoço"}')
echo "$PIX" | grep -q authCode && ok "Pix enviado" || fail "Pix falhou" "$PIX"

echo "=== 14. Pix acima do saldo deve ser recusado ==="
OVER=$(curl -s -X POST $API/v1/pix/send -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"pixKey":"amigo@email.com","amountCents":99999999}')
echo "$OVER" | grep -qE "SALDO_INSUFICIENTE|LIMITE_NOTURNO" && ok "Pix acima do saldo recusado" || fail "Pix passou sem saldo!" "$OVER"

echo "=== 15. Cofrinho: criar, guardar, resgatar ==="
GOAL=$(curl -s -X POST $API/v1/goals -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"name":"Viagem","targetCents":800000,"symbol":"airplane"}')
GOAL_ID=$(echo "$GOAL" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
curl -s -X POST "$API/v1/goals/$GOAL_ID/deposit" -H "$AUTH" -H 'Content-Type: application/json' -d '{"amountCents":100000}' >/dev/null
SAVED=$(curl -s $API/v1/goals -H "$AUTH" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['savedCents'])")
[ "$SAVED" = "100000" ] && ok "guardou R\$ 1.000,00 no cofrinho" || fail "cofrinho: $SAVED" ""

OVERW=$(curl -s -X POST "$API/v1/goals/$GOAL_ID/withdraw" -H "$AUTH" -H 'Content-Type: application/json' -d '{"amountCents":500000}')
echo "$OVERW" | grep -q SALDO_INSUFICIENTE && ok "resgate acima do guardado recusado" || fail "resgatou demais!" "$OVERW"

echo "=== 16. Investir e resgatar ==="
curl -s -X POST $API/v1/investments/cdb/invest -H "$AUTH" -H 'Content-Type: application/json' -d '{"amountCents":50000}' >/dev/null
POS=$(curl -s $API/v1/investments/positions -H "$AUTH" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['current']['amount'] if d else 'vazio')" 2>/dev/null)
[ -n "$POS" ] && ok "investiu, posição atual: $POS" || fail "investimento falhou" ""

echo "=== 17. Cartão: compra engorda a fatura ==="
curl -s -X POST $API/v1/card/purchase -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"amountCents":8740,"merchant":"Mercado Pão Fresco","category":"mercado"}' >/dev/null
CARD=$(curl -s $API/v1/card -H "$AUTH")
INV=$(echo "$CARD" | python3 -c "import json,sys; print(int(float(json.load(sys.stdin)['invoice']['amount'])*100))" 2>/dev/null)
[ "$INV" = "8740" ] && ok "fatura acumulou R\$ 87,40" || fail "fatura: $INV centavos" "$CARD"

echo "=== 18. Pagar fatura ==="
curl -s -X POST $API/v1/card/invoice/pay -H "$AUTH" >/dev/null
INV2=$(curl -s $API/v1/card -H "$AUTH" | python3 -c "import json,sys; print(int(float(json.load(sys.stdin)['invoice']['amount'])*100))" 2>/dev/null)
[ "$INV2" = "0" ] && ok "fatura zerada após pagamento" || fail "fatura pós-pagamento: $INV2 centavos" ""

echo "=== 19. Pagar parcela do empréstimo ==="
PAY=$(curl -s -X POST "$API/v1/credit/loans/$LOAN_ID/pay" -H "$AUTH")
echo "$PAY" | grep -q authCode && ok "parcela paga" || fail "pagamento de parcela falhou" "$PAY"
PAID=$(curl -s $API/v1/credit/loans -H "$AUTH" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['paidCount'])")
[ "$PAID" = "1" ] && ok "1 parcela registrada como paga" || fail "paidCount=$PAID" ""

echo "=== 20. Extrato e gastos por categoria ==="
ST=$(curl -s "$API/v1/statement?limit=50" -H "$AUTH" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['transactions']))")
ok "extrato com $ST transações"
SP=$(curl -s "$API/v1/statement/spending" -H "$AUTH")
echo "$SP" | grep -q mercado && ok "gastos por categoria derivam das transações" || echo "  ℹ️  gastos: $SP"

echo "=== 21. Logout mantém o dispositivo ==="
curl -s -X POST $API/v1/auth/logout -H 'Content-Type: application/json' -d "{\"refreshToken\":\"$REFRESH\"}" >/dev/null
RELOGIN=$(curl -s -X POST $API/v1/auth/login/pin -H 'Content-Type: application/json' -d "{
  \"cpf\":\"52998224725\",\"pin\":\"2846\",
  \"device\":{\"hardwareId\":\"iphone-juan-01\",\"name\":\"iPhone de Juan\"}}")
TOKEN2=$(echo "$RELOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin).get('accessToken',''))" 2>/dev/null)
DEVS=$(curl -s $API/v1/auth/devices -H "Authorization: Bearer $TOKEN2" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null)
[ "$DEVS" = "1" ] && ok "voltou e o aparelho continua vinculado (1 device)" || fail "devices=$DEVS" ""

echo
echo "=== SALDO GLOBAL DO RAZÃO (deve ser ZERO) ==="
