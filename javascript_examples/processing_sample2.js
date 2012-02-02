width = 640;
height = 480;

drawer = new DrawPath(width, height);
drawer.start();

// comment the following lines if you don't want 
// the output window to be automatically created
output = new VideoOutput(width, height);
drawer.outputPin('frame').connect(output.inputPin('frame'));

// uncomment the following line if you want the outputframe exported on the board
//drawer.outputPin('frame').export();


function sketchProc(processing) {
  // set canvas size known by processing
  processing.width = width;
  processing.height = height;
  //processing.size( 200, 200 );
  // Override draw function, by default it will be called 60 times per second
  processing.draw = function() {
    // determine center and max clock arm length
    var centerX = processing.width / 2, centerY = processing.height / 2;
    var maxArmLength = Math.min(centerX, centerY);

    function drawArm(position, lengthScale, weight) {
      processing.strokeWeight(weight);
      processing.line(centerX, centerY,
        centerX + Math.sin(position * 2 * Math.PI) * lengthScale * maxArmLength,
        centerY - Math.cos(position * 2 * Math.PI) * lengthScale * maxArmLength);
    }

    // erase background
    processing.background(224);

    var now = new Date();

    // Moving hours arm by small increments
    var hoursPosition = (now.getHours() % 12 + now.getMinutes() / 60) / 12;
    drawArm(hoursPosition, 0.5, 5);

    // Moving minutes arm by small increments
    var minutesPosition = (now.getMinutes() + now.getSeconds() / 60) / 60;
    drawArm(minutesPosition, 0.80, 3);

    // Moving hour arm by second increments
    var secondsPosition = now.getSeconds() / 60;
    drawArm(secondsPosition, 0.90, 1);
  };
}

//var canvas = $('canvas:first', drawer).get(0);
// attaching the sketchProc function to the canvas
var processingInstance = new Processing(drawer.canvas, sketchProc);