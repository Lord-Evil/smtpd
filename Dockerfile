# docker build -t hub.mega-bot.com/smtpd --no-cache .
FROM ubuntu
WORKDIR /app
COPY ./config.json.sample ./config.json
ADD ./smtpd .
CMD ["./smtpd"]
